extends CompositorEffect

# Auto exposure (hakoniwa-scenario memo 027; the formula is a copy of
# hakoniwa_scenario/sensors/exposure.py). On linear values after the lens effects and
# before white balance, every view drawn for a frame:
#   - counts each pixel's luminance (cd/m2: pixel / base normalization) into a log2
#     histogram on the GPU
#   - multiplies the pixel by the gain of the exposure metered on earlier frames
# After the frame, end_frame reads the histogram, meters the luminance between two
# percentiles, takes the ISO 2720 exposure for it and moves the camera's exposure
# toward it at adaptation_speed stops per second of simulation time. The camera itself
# draws at a fixed base exposure; the gain is 2^(EV_base - EV_auto). Views of one frame
# (cube faces) share the exposure, so faces do not differ in brightness.

const BINS := 256
const LOG2_MIN := -4.0
const LOG2_MAX := 32.0
const METER_CONSTANT_K := 12.5

const SHADER_CODE := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 0, binding = 1, std430) restrict buffer Histogram {
	uint counts[256];
} histogram;
layout(push_constant, std430) uniform Params {
	vec2 size;
	float base_normalization;
	float gain;
} params;

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	if (pixel.x >= int(params.size.x) || pixel.y >= int(params.size.y)) {
		return;
	}
	vec4 color = imageLoad(color_image, pixel);
	float luminance = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722)) / params.base_normalization;
	float position = (log2(max(luminance, exp2(-4.0))) + 4.0) / 36.0 * 256.0;
	uint bin = uint(clamp(floor(position), 0.0, 255.0));
	atomicAdd(histogram.counts[bin], 1u);
	color.rgb *= params.gain;
	imageStore(color_image, pixel, color);
}
"""

var base_ev100 := 0.0
var low_percentile := 10.0
var high_percentile := 90.0
var speed_stops_per_s := 2.0
var compensation_ev := 0.0
var ev100_min := -4.0
var ev100_max := 22.0
# Exposure (EV100) of each camera, by camera name; the camera of the frame being drawn.
var _ev100 := {}
var _camera := ""
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _histogram: RID

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	# CompositorEffect.enabled: on only for profiles with auto exposure.
	enabled = false
	_rd = RenderingServer.get_rendering_device()
	# No RenderingDevice (--headless, Compatibility renderer): nothing to draw.
	if _rd != null:
		RenderingServer.call_on_render_thread(_create_pipeline)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		for rid in [_shader, _histogram]:
			if rid.is_valid():
				_rd.free_rid(rid)

func _create_pipeline() -> void:
	var source := RDShaderSource.new()
	source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	source.source_compute = SHADER_CODE
	var spirv := _rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():
		push_error("auto exposure shader: " + spirv.compile_error_compute)
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	_histogram = _rd.storage_buffer_create(BINS * 4, PackedByteArray())

# The camera of the next frame; its exposure is applied to every view drawn for it.
func begin_frame(camera_name: String) -> void:
	_camera = camera_name

func current_ev100() -> float:
	return _ev100.get(_camera, base_ev100)

func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	if not enabled or not _pipeline.is_valid():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	var gain := pow(2.0, base_ev100 - current_ev100())
	var push := PackedFloat32Array([size.x, size.y, normalization(base_ev100), gain]).to_byte_array()
	for view in buffers.get_view_count():
		var color_uniform := RDUniform.new()
		color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		color_uniform.binding = 0
		color_uniform.add_id(buffers.get_color_layer(view))
		var histogram_uniform := RDUniform.new()
		histogram_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		histogram_uniform.binding = 1
		histogram_uniform.add_id(_histogram)
		var uniform_set := UniformSetCacheRD.get_cache(_shader, 0, [color_uniform, histogram_uniform])
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipeline)
		_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
		_rd.compute_list_end()

# After a frame is drawn and read back: meter its histogram and adapt the camera's
# exposure over dt_s seconds of simulation time. The first frame of a camera sets the
# exposure directly (nothing to adapt from).
func end_frame(dt_s: float) -> void:
	if not enabled or not _histogram.is_valid():
		return
	var counts := _rd.buffer_get_data(_histogram).to_int32_array()
	_rd.buffer_clear(_histogram, 0, BINS * 4)
	var metered = metered_log2(counts, low_percentile, high_percentile)
	if metered == null:
		return
	var target := target_ev100(metered, compensation_ev, ev100_min, ev100_max)
	if _ev100.has(_camera):
		_ev100[_camera] = adapt(_ev100[_camera], target, speed_stops_per_s, dt_s)
	else:
		_ev100[_camera] = target
	print("AUTO_EXPOSURE camera=%s metered_log2=%.3f target_ev100=%.3f ev100=%.3f" % [_camera, metered, target, _ev100[_camera]])

static func bin_centre(index: int) -> float:
	return LOG2_MIN + (index + 0.5) * (LOG2_MAX - LOG2_MIN) / BINS

# Mean log2 luminance of the pixels between the two percentiles (null if empty).
static func metered_log2(counts: PackedInt32Array, low: float, high: float):
	var total := 0.0
	for c in counts:
		total += c
	if total == 0.0:
		return null
	var low_count := total * low / 100.0
	var high_count := total * high / 100.0
	var below := 0.0
	var weight := 0.0
	var weighted := 0.0
	for index in counts.size():
		var start := below
		var end := below + counts[index]
		var inside := maxf(0.0, minf(end, high_count) - maxf(start, low_count))
		weight += inside
		weighted += inside * bin_centre(index)
		below = end
	return weighted / weight if weight > 0.0 else null

# ISO 2720: EV100 = log2(L 100 / K), lowered by the compensation, clamped.
static func target_ev100(metered: float, compensation: float, low: float, high: float) -> float:
	return clampf(metered + log(100.0 / METER_CONSTANT_K) / log(2.0) - compensation, low, high)

static func adapt(current: float, target: float, speed: float, dt_s: float) -> float:
	var step := speed * dt_s
	return current + clampf(target - current, -step, step)

static func normalization(ev100: float) -> float:
	return 1.0 / (1.2 * pow(2.0, ev100))
