extends CompositorEffect

# Fog on linear scene values, before the lens effects, white balance and the tone map
# (hakoniwa-scenario memo 027): Koschmieder's law per pixel,
#   L_out = T(d) L_scene + (1 - T(d)) L_fog,  T(d) = exp(-beta d),
# d the distance from the camera to the surface (from the depth buffer), beta from the
# meteorological visibility. L_fog is the airlight in cd/m2 times the camera's exposure
# normalization, so the fog follows the exposure like the scene does. Godot's own fog is
# not used: it draws the fog colour without the camera exposure (measured; also Godot
# issue #106527), and a later fix there would change our images.
# RGB only: MuJoCo's depth and segmentation stay geometric.

const SHADER_CODE := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_texture;
layout(push_constant, std430) uniform Params {
	mat4 inverse_projection;
	vec2 size;
	float beta;
	float airlight;
} params;

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	if (pixel.x >= int(params.size.x) || pixel.y >= int(params.size.y)) {
		return;
	}
	vec2 uv = (vec2(pixel) + 0.5) / params.size;
	float depth = texture(depth_texture, uv).r;
	vec4 ndc = vec4(uv * 2.0 - 1.0, depth, 1.0);
	vec4 view = params.inverse_projection * ndc;
	// The sky (no surface) is infinitely far: all airlight.
	float distance = view.w != 0.0 ? length(view.xyz / view.w) : 1.0e30;
	float transmittance = exp(-params.beta * distance);
	vec4 color = imageLoad(color_image, pixel);
	color.rgb = color.rgb * transmittance + vec3(params.airlight) * (1.0 - transmittance);
	imageStore(color_image, pixel, color);
}
"""

var beta := 0.0
# Airlight in cd/m2 (neutral) and the camera's exposure normalization for this frame.
var airlight_nits := 0.0
var exposure_normalization := 1.0
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sampler: RID

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	_rd = RenderingServer.get_rendering_device()
	# No RenderingDevice (--headless, Compatibility renderer): nothing to draw.
	if _rd != null:
		RenderingServer.call_on_render_thread(_create_pipeline)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		for rid in [_shader, _sampler]:
			if rid.is_valid():
				_rd.free_rid(rid)

func _create_pipeline() -> void:
	var source := RDShaderSource.new()
	source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	source.source_compute = SHADER_CODE
	var spirv := _rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():
		push_error("fog shader: " + spirv.compile_error_compute)
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	var state := RDSamplerState.new()
	state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_sampler = _rd.sampler_create(state)

func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	if beta <= 0.0 or not _pipeline.is_valid():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	var scene_data := render_data.get_render_scene_data()
	for view in buffers.get_view_count():
		var inverse := scene_data.get_view_projection(view).inverse()
		var push := PackedFloat32Array()
		for column in 4:
			for row in 4:
				push.append(inverse[column][row])
		push.append_array([size.x, size.y, beta, airlight_nits * exposure_normalization])
		var color_uniform := RDUniform.new()
		color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		color_uniform.binding = 0
		color_uniform.add_id(buffers.get_color_layer(view))
		var depth_uniform := RDUniform.new()
		depth_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		depth_uniform.binding = 1
		depth_uniform.add_id(_sampler)
		depth_uniform.add_id(buffers.get_depth_layer(view))
		var uniform_set := UniformSetCacheRD.get_cache(_shader, 0, [color_uniform, depth_uniform])
		var bytes := push.to_byte_array()
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipeline)
		_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
		_rd.compute_list_set_push_constant(list, bytes, bytes.size())
		_rd.compute_list_dispatch(list, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
		_rd.compute_list_end()
