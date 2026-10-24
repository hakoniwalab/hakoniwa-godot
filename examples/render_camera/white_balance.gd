extends CompositorEffect

# White balance on linear scene values, before auto exposure, glow and the tone map
# (Godot runs post-transparent compositor effects before its post-processing).
# A camera balances the sensor's RGB; doing it after the tone map (Godot's colour
# correction) would act on curved values. hakoniwa-scenario memo 024, step 3.
#
# temperature_k is the colour temperature of the light that comes out white (CARLA/UE
# temp, 6500 = no change): a lower value turns the picture bluer. tint is the light's
# tint across the locus that comes out white (magenta > 0 > green): a positive value
# turns the picture greener (UE's WhiteTint compensates the same way).

const ColorTemperature = preload("res://color_temperature.gd")
const REFERENCE_KELVIN := 6500.0
# UE's white balance moves the white point by tint x 0.05 in CIE 1960 uv.
const TINT_UV_SCALE := 0.05

const SHADER_CODE := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(push_constant, std430) uniform Params {
	vec4 gains;
	vec2 size;
	vec2 unused;
} params;

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	if (pixel.x >= int(params.size.x) || pixel.y >= int(params.size.y)) {
		return;
	}
	vec4 color = imageLoad(color_image, pixel);
	color.rgb *= params.gains.rgb;
	imageStore(color_image, pixel, color);
}
"""

var gains := Vector3.ONE
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	_rd = RenderingServer.get_rendering_device()
	RenderingServer.call_on_render_thread(_create_pipeline)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _shader.is_valid():
		_rd.free_rid(_shader)

# Compiled from source at run time: a .glsl file needs the editor's import, which a
# run does not do.
func _create_pipeline() -> void:
	var source := RDShaderSource.new()
	source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	source.source_compute = SHADER_CODE
	var spirv := _rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():
		push_error("white balance shader: " + spirv.compile_error_compute)
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)

func set_white_balance(temperature_k: float, tint: float) -> void:
	gains = gains_for(temperature_k, tint)

func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	if not _pipeline.is_valid() or gains.is_equal_approx(Vector3.ONE):
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	var push := PackedFloat32Array([gains.x, gains.y, gains.z, 0.0, size.x, size.y, 0.0, 0.0]).to_byte_array()
	for view in buffers.get_view_count():
		var image_uniform := RDUniform.new()
		image_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		image_uniform.binding = 0
		image_uniform.add_id(buffers.get_color_layer(view))
		var uniform_set := UniformSetCacheRD.get_cache(_shader, 0, [image_uniform])
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipeline)
		_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
		_rd.compute_list_end()

# Per-channel gains (linear sRGB) that make light of temperature_k (and tint) white:
# white(6500 K) / white(temperature_k), so 6500 K and tint 0 give exactly 1. Both whites
# have luminance 1, so light that comes out white keeps its luminance (a grey card stays
# as bright). White follows color_temperature.gd (daylight locus from 4000 K).
static func gains_for(temperature_k: float, tint: float) -> Vector3:
	var reference: Vector3 = ColorTemperature.white_rgb(REFERENCE_KELVIN)
	var white: Vector3 = ColorTemperature.white_rgb(temperature_k, tint, TINT_UV_SCALE)
	return Vector3(reference.x / white.x, reference.y / white.y, reference.z / white.z)
