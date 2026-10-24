extends CompositorEffect

# Lens effects on scene values, before white balance and the tone map, defined on the
# output image (hakoniwa-scenario memo 024 step 4, memo 025):
#   - vignetting: illumination relative to the optical axis (cx, cy), 1 / (1 + k^2 rho^2)^2
#     with rho = distance from (cx, cy) in the output image / fx (tan theta for a pinhole:
#     the cos^4 law); k so the farthest image corner gets vignette_corner (1 = none)
#   - lateral chromatic aberration: red and blue displaced from green by
#     chromatic_aberration_px at that corner (red outward, blue inward), linear in
#     the distance from (cx, cy)
# RGB only: MuJoCo's depth and segmentation keep the geometric reference.
#
# The image drawn here is not always the output image: a lens that is not an ideal
# pinhole draws a wider pinhole image or cube faces first (memo 025). For each pixel
# drawn, the shader finds where its ray lands in the output image (the lens's forward
# projection, a copy of hakoniwa_scenario/sensors/lens.py project), applies the
# vignetting there, and converts the output-image aberration shift to this image with
# the local derivative of that projection. Near a cube face edge the shifted read
# stays inside the face (the neighbouring face is another image).
# The colour image is copied first because aberration reads neighbouring pixels
# (with a small compute pass: Godot's colour image cannot be a texture_copy source).

const SHADER_CODE := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(rgba16f, set = 0, binding = 1) uniform readonly image2D source_image;
layout(set = 0, binding = 2, std430) restrict readonly buffer Params {
	// 0-4: drawn image width, height, focal, cx, cy (pixel centres at integers)
	// 5-13: drawn view axes x_f, y_f, z_f in the output camera's optical frame
	// 14-30: output lens fx, fy, cx, cy, skew, projection, use_brown, k1, k2, p1, p2, k3,
	//        kb0..kb3, cutoff angle
	// 31-33: vignette k^2, aberration px at the corner, corner distance px
	float v[];
} params;

const float PI = 3.14159265358979;

vec4 load_clamped(ivec2 pixel) {
	return imageLoad(source_image, clamp(pixel, ivec2(0), ivec2(params.v[0], params.v[1]) - 1));
}

// Bilinear read at a pixel position (pixel centres at integers).
vec4 load_bilinear(vec2 position) {
	ivec2 base = ivec2(floor(position));
	vec2 f = position - vec2(base);
	vec4 top = mix(load_clamped(base), load_clamped(base + ivec2(1, 0)), f.x);
	vec4 bottom = mix(load_clamped(base + ivec2(0, 1)), load_clamped(base + ivec2(1, 1)), f.x);
	return mix(top, bottom, f.y);
}

float image_radius(int projection, float theta) {
	if (projection == 0) return tan(theta);
	if (projection == 1) return theta;
	if (projection == 2) return 2.0 * sin(theta / 2.0);
	if (projection == 3) return 2.0 * tan(theta / 2.0);
	if (projection == 4) return sin(theta);
	float t2 = theta * theta;
	return theta * (1.0 + t2 * (params.v[26] + t2 * (params.v[27] + t2 * (params.v[28] + t2 * params.v[29]))));
}

// Output image position of a ray (camera optical frame); false when the lens does not see it.
bool project_output(vec3 ray, out vec2 position) {
	int projection = int(params.v[19]);
	float theta = atan(length(ray.xy), ray.z);
	if (theta > params.v[30]) return false;
	vec2 d;
	if (projection == 0) {
		if (ray.z <= 0.0) return false;
		d = ray.xy / ray.z;
		if (params.v[20] > 0.5) {
			float r2 = dot(d, d);
			float radial = 1.0 + r2 * (params.v[21] + r2 * (params.v[22] + r2 * params.v[25]));
			d = vec2(d.x * radial + 2.0 * params.v[23] * d.x * d.y + params.v[24] * (r2 + 2.0 * d.x * d.x),
				d.y * radial + params.v[23] * (r2 + 2.0 * d.y * d.y) + 2.0 * params.v[24] * d.x * d.y);
		}
	} else {
		if (projection == 4 && theta > PI / 2.0) return false;
		float rho = length(ray.xy);
		d = rho > 0.0 ? ray.xy * (image_radius(projection, theta) / rho) : vec2(0.0);
	}
	position = vec2(params.v[14] * d.x + params.v[18] * d.y + params.v[16], params.v[15] * d.y + params.v[17]);
	return true;
}

// Ray of a drawn-image position, in the output camera's optical frame.
vec3 drawn_ray(vec2 position) {
	vec3 local = vec3((position.x - params.v[3]) / params.v[2], (position.y - params.v[4]) / params.v[2], 1.0);
	mat3 axes = mat3(vec3(params.v[5], params.v[6], params.v[7]), vec3(params.v[8], params.v[9], params.v[10]),
		vec3(params.v[11], params.v[12], params.v[13]));
	return axes * local;
}

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	if (pixel.x >= int(params.v[0]) || pixel.y >= int(params.v[1])) {
		return;
	}
	vec2 position = vec2(pixel);
	vec4 color = imageLoad(source_image, pixel);
	vec2 output_position;
	if (!project_output(drawn_ray(position), output_position)) {
		imageStore(color_image, pixel, color);
		return;
	}
	vec2 centre = vec2(params.v[16], params.v[17]);
	vec2 offset = output_position - centre;
	if (params.v[32] > 0.0) {
		// Output-image shift, converted to this image with the projection's local
		// derivative (one-pixel differences): the red seen here came from further in.
		vec2 shift = offset / params.v[33] * params.v[32];
		vec2 px, py;
		if (project_output(drawn_ray(position + vec2(1.0, 0.0)), px) && project_output(drawn_ray(position + vec2(0.0, 1.0)), py)) {
			mat2 jacobian = mat2(px - output_position, py - output_position);
			vec2 drawn_shift = inverse(jacobian) * shift;
			color.r = load_bilinear(position - drawn_shift).r;
			color.b = load_bilinear(position + drawn_shift).b;
		}
	}
	float rho_squared = dot(offset, offset) / (params.v[14] * params.v[14]);
	float falloff = 1.0 + params.v[31] * rho_squared;
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
const PARAM_COUNT := 64

var vignette_corner := 1.0
var aberration_px := 0.0
# The output lens (lens.gd) and how the image drawn now relates to it.
var lens = null
var drawn_focal := 1.0
var main_basis := Basis.IDENTITY
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _copy_shader: RID
var _copy_pipeline: RID
var _params: RID

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	_rd = RenderingServer.get_rendering_device()
	# No RenderingDevice (--headless, Compatibility renderer): nothing to draw.
	if _rd != null:
		RenderingServer.call_on_render_thread(_create_pipeline)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		for rid in [_shader, _copy_shader, _params]:
			if rid.is_valid():
				_rd.free_rid(rid)

func _create_pipeline() -> void:
	_shader = _compile(SHADER_CODE, "lens effects shader")
	_copy_shader = _compile(COPY_SHADER_CODE, "lens effects copy shader")
	if _shader.is_valid() and _copy_shader.is_valid():
		_pipeline = _rd.compute_pipeline_create(_shader)
		_copy_pipeline = _rd.compute_pipeline_create(_copy_shader)
		var zeros := PackedFloat32Array()
		zeros.resize(PARAM_COUNT)
		_params = _rd.storage_buffer_create(PARAM_COUNT * 4, zeros.to_byte_array())

func _compile(code: String, label: String) -> RID:
	var source := RDShaderSource.new()
	source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	source.source_compute = code
	var spirv := _rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():
		push_error(label + ": " + spirv.compile_error_compute)
		return RID()
	return _rd.shader_create_from_spirv(spirv)

func set_effects(effects: Dictionary) -> void:
	vignette_corner = float(effects.get("vignette_corner", 1.0))
	aberration_px = float(effects.get("chromatic_aberration_px", 0.0))

# The output lens, the focal length of the image(s) drawn for it, and the main camera's
# basis (cube face cameras are found relative to it).
func set_geometry(output_lens, focal_px: float, camera_basis: Basis) -> void:
	lens = output_lens
	drawn_focal = focal_px
	main_basis = camera_basis

func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	if lens == null or not _pipeline.is_valid() or not _copy_pipeline.is_valid() or (vignette_corner >= 1.0 and aberration_px <= 0.0):
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	var camera_basis := render_data.get_render_scene_data().get_cam_transform().basis
	_rd.buffer_update(_params, 0, PARAM_COUNT * 4, _parameters(size, camera_basis).to_byte_array())
	var copy_push := PackedFloat32Array([size.x, size.y, 0.0, 0.0]).to_byte_array()
	for view in buffers.get_view_count():
		var color := buffers.get_color_layer(view)
		var copy := _source_texture(buffers, color, size)
		_dispatch(_copy_shader, _copy_pipeline, [copy, color], copy_push, size)
		_dispatch(_shader, _pipeline, [color, copy], PackedByteArray(), size, _params)

func _parameters(size: Vector2i, camera_basis: Basis) -> PackedFloat32Array:
	var p := PackedFloat32Array()
	p.resize(PARAM_COUNT)
	p[0] = size.x
	p[1] = size.y
	p[2] = drawn_focal
	p[3] = (size.x - 1) / 2.0
	p[4] = (size.y - 1) / 2.0
	# This view's axes in the output camera's optical frame: Godot's camera axes are
	# optical x, -y, -z, and optical (x, y, z) is Godot local (x, -y, -z).
	var relative := main_basis.inverse() * camera_basis
	var to_optical := func(v: Vector3) -> Vector3: return Vector3(v.x, -v.y, -v.z)
	var axes: Array = [to_optical.call(relative.x), to_optical.call(-relative.y), to_optical.call(-relative.z)]
	for i in 3:
		p[5 + 3 * i] = axes[i].x
		p[6 + 3 * i] = axes[i].y
		p[7 + 3 * i] = axes[i].z
	p[14] = lens.fx
	p[15] = lens.fy
	p[16] = lens.cx
	p[17] = lens.cy
	p[18] = lens.skew
	p[19] = lens.PROJECTION_IDS[lens.projection]
	p[20] = 1.0 if lens.distortion == "brown_conrady" else 0.0
	for i in 5:
		p[21 + i] = lens.brown[i]
	for i in 4:
		p[26 + i] = lens.kb[i]
	p[30] = lens.cutoff_angle
	# The farthest image corner from the optical axis sets the vignetting k and the
	# aberration scale.
	var corner := 0.0
	for c in [Vector2(0, 0), Vector2(lens.width - 1, 0), Vector2(0, lens.height - 1), Vector2(lens.width - 1, lens.height - 1)]:
		corner = maxf(corner, (c - Vector2(lens.cx, lens.cy)).length())
	var rho_corner_squared: float = (corner * corner) / (lens.fx * lens.fx)
	p[31] = (1.0 / sqrt(vignette_corner) - 1.0) / rho_corner_squared
	p[32] = aberration_px
	p[33] = corner
	return p

# One compute pass: images[0] is written, images[1] read; an optional storage buffer.
func _dispatch(shader: RID, pipeline: RID, images: Array, push: PackedByteArray, size: Vector2i, buffer := RID()) -> void:
	var uniforms: Array[RDUniform] = []
	for i in images.size():
		var image_uniform := RDUniform.new()
		image_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		image_uniform.binding = i
		image_uniform.add_id(images[i])
		uniforms.append(image_uniform)
	if buffer.is_valid():
		var buffer_uniform := RDUniform.new()
		buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		buffer_uniform.binding = 2
		buffer_uniform.add_id(buffer)
		uniforms.append(buffer_uniform)
	var uniform_set := UniformSetCacheRD.get_cache(shader, 0, uniforms)
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, pipeline)
	_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	if not push.is_empty():
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
