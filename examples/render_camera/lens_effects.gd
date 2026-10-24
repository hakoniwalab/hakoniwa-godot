extends CompositorEffect

# Lens effects on scene values, before white balance and the tone map
# (hakoniwa-scenario memo 024, step 4):
#   - vignetting: illumination at the image corner relative to the centre
#     (vignette_corner, 1 = none), shaped like natural vignetting (cos^4 law):
#     1 / (1 + (k tan theta)^2)^2, k chosen so the corner gets vignette_corner
#   - lateral chromatic aberration: red and blue displaced from green by
#     chromatic_aberration_px at the image corner (red outward, blue inward),
#     growing linearly from the centre
# The colour image is copied first because aberration reads neighbouring pixels
# (with a small compute pass: Godot's colour image cannot be a texture_copy source).

const SHADER_CODE := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(rgba16f, set = 0, binding = 1) uniform readonly image2D source_image;
layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 centre;
	float focal_px;
	float k_squared;
	float aberration_px;
	float corner_px;
} params;

vec4 load_clamped(ivec2 pixel) {
	return imageLoad(source_image, clamp(pixel, ivec2(0), ivec2(params.size) - 1));
}

// Bilinear read at a position in pixel units (pixel centres at +0.5).
vec4 load_bilinear(vec2 position) {
	vec2 p = position - 0.5;
	ivec2 base = ivec2(floor(p));
	vec2 f = p - vec2(base);
	vec4 top = mix(load_clamped(base), load_clamped(base + ivec2(1, 0)), f.x);
	vec4 bottom = mix(load_clamped(base + ivec2(0, 1)), load_clamped(base + ivec2(1, 1)), f.x);
	return mix(top, bottom, f.y);
}

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	if (pixel.x >= int(params.size.x) || pixel.y >= int(params.size.y)) {
		return;
	}
	vec2 position = vec2(pixel) + 0.5;
	vec2 offset = position - params.centre;
	vec4 color = imageLoad(source_image, pixel);
	if (params.aberration_px > 0.0) {
		// The red image is moved outward: the red seen here came from further in.
		vec2 shift = offset / params.corner_px * params.aberration_px;
		color.r = load_bilinear(position - shift).r;
		color.b = load_bilinear(position + shift).b;
	}
	float tan_squared = dot(offset, offset) / (params.focal_px * params.focal_px);
	float falloff = 1.0 + params.k_squared * tan_squared;
	color.rgb /= falloff * falloff;
	imageStore(color_image, pixel, color);
}
"""

const COPY_SHADER_CODE := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform writeonly image2D copy_image;
layout(rgba16f, set = 0, binding = 1) uniform readonly image2D color_image;
layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 unused;
} params;

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	if (pixel.x >= int(params.size.x) || pixel.y >= int(params.size.y)) {
		return;
	}
	imageStore(copy_image, pixel, imageLoad(color_image, pixel));
}
"""

const CONTEXT := &"hakoniwa_lens_effects"
const SOURCE := &"source"

var vignette_corner := 1.0
var aberration_px := 0.0
var horizontal_fov := 1.0
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _copy_shader: RID
var _copy_pipeline: RID

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	_rd = RenderingServer.get_rendering_device()
	# No RenderingDevice (--headless, Compatibility renderer): nothing to draw.
	if _rd != null:
		RenderingServer.call_on_render_thread(_create_pipeline)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		for shader in [_shader, _copy_shader]:
			if shader.is_valid():
				_rd.free_rid(shader)

func _create_pipeline() -> void:
	_shader = _compile(SHADER_CODE, "lens effects shader")
	_copy_shader = _compile(COPY_SHADER_CODE, "lens effects copy shader")
	if _shader.is_valid() and _copy_shader.is_valid():
		_pipeline = _rd.compute_pipeline_create(_shader)
		_copy_pipeline = _rd.compute_pipeline_create(_copy_shader)

func _compile(code: String, label: String) -> RID:
	var source := RDShaderSource.new()
	source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	source.source_compute = code
	var spirv := _rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():
		push_error(label + ": " + spirv.compile_error_compute)
		return RID()
	return _rd.shader_create_from_spirv(spirv)

func set_effects(effects: Dictionary, horizontal_fov_rad: float) -> void:
	vignette_corner = float(effects.get("vignette_corner", 1.0))
	aberration_px = float(effects.get("chromatic_aberration_px", 0.0))
	horizontal_fov = horizontal_fov_rad

func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	if not _pipeline.is_valid() or not _copy_pipeline.is_valid() or (vignette_corner >= 1.0 and aberration_px <= 0.0):
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	var centre := Vector2(size) * 0.5
	var focal_px := size.x * 0.5 / tan(horizontal_fov * 0.5)
	var corner_px := centre.length()
	# k so that 1 / (1 + k^2 tan^2(corner))^2 = vignette_corner.
	var tan_corner_squared := (corner_px * corner_px) / (focal_px * focal_px)
	var k_squared := (1.0 / sqrt(vignette_corner) - 1.0) / tan_corner_squared
	var push := PackedFloat32Array([size.x, size.y, centre.x, centre.y, focal_px, k_squared, aberration_px, corner_px]).to_byte_array()
	var copy_push := PackedFloat32Array([size.x, size.y, 0.0, 0.0]).to_byte_array()
	for view in buffers.get_view_count():
		var color := buffers.get_color_layer(view)
		var copy := _source_texture(buffers, color, size)
		_dispatch(_copy_shader, _copy_pipeline, copy, color, copy_push, size)
		_dispatch(_shader, _pipeline, color, copy, push, size)

# One compute pass writing image binding 0 from image binding 1.
func _dispatch(shader: RID, pipeline: RID, target: RID, source: RID, push: PackedByteArray, size: Vector2i) -> void:
	var target_uniform := RDUniform.new()
	target_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	target_uniform.binding = 0
	target_uniform.add_id(target)
	var source_uniform := RDUniform.new()
	source_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	source_uniform.binding = 1
	source_uniform.add_id(source)
	var uniform_set := UniformSetCacheRD.get_cache(shader, 0, [target_uniform, source_uniform])
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, pipeline)
	_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	_rd.compute_list_end()

# A copy of the colour image, kept by the render buffers (recreated when the size changes).
func _source_texture(buffers: RenderSceneBuffersRD, color: RID, size: Vector2i) -> RID:
	if buffers.has_texture(CONTEXT, SOURCE):
		var existing := buffers.get_texture(CONTEXT, SOURCE)
		var format := _rd.texture_get_format(existing)
		if format.width == size.x and format.height == size.y:
			return existing
		buffers.clear_context(CONTEXT)
	var color_format := _rd.texture_get_format(color)
	var usage := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	return buffers.create_texture(CONTEXT, SOURCE, color_format.format, usage, RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, true, false)
