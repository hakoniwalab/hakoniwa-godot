extends RefCounted

const ColorTemperature = preload("res://color_temperature.gd")
const SunModel = preload("res://sun_model.gd")
const SkyModel = preload("res://sky_model.gd")

# Daylight in physical units (C3, hakoniwa-scenario memo 024): the sun in lux, the sky
# in nits, ambient and reflections from the sky, and a camera with physical exposure
# (ISO, shutter, aperture). With these, exposure values mean what they mean on a real
# camera (Sunny 16: ISO 100, f/16, 1/100 s on a sunny day gives a mid-grey 18 % card).
# Needs rendering/lights_and_shadows/use_physical_light_units in project.godot.
#
# Godot world frame here: X = East, Y = Up, Z = -North (the city GLB's local ENU).

const DEFAULT_LATITUDE := 35.689245     # the Urban Tocho origin
const DEFAULT_LONGITUDE := 139.690808
const DEFAULT_TIME := "2026-10-24T12:00:00+09:00"
const DEFAULT_SUN_LUX := 100000.0       # direct sun, clear day
const DEFAULT_SUN_KELVIN := 5800.0
# Godot sizes the image sensor so that fov = 2 atan(12 mm / focal length) (a 24 mm frame);
# with KEEP_WIDTH that angle is the horizontal one.
const HALF_SENSOR_MM := 12.0

var latitude := DEFAULT_LATITUDE
var longitude := DEFAULT_LONGITUDE
var time_text := DEFAULT_TIME
var sun_lux := DEFAULT_SUN_LUX
var sun_kelvin := DEFAULT_SUN_KELVIN
var sky_material: ShaderMaterial
# The sun as seen: angular diameter 0.53 deg; its luminance is the sun's illuminance
# (normal to the sun) over the disk's solid angle (cie_sky.gdshader, memo 027).
const SUN_ANGULAR_DIAMETER := deg_to_rad(0.53)
var current_sun_lux := DEFAULT_SUN_LUX
var sun: DirectionalLight3D
# Auto exposure speed, stops per second of simulation time, when the profile has no
# exposure.adaptation_speed; --auto-exposure-speed= changes it for tests.
var auto_exposure_speed := 2.0
# Weather (C5, hakoniwa-scenario memo 027), OpenSCENARIO Weather names: a JSON file
# given with --weather=. Fog: fog.visualRange (m).
var weather := {}
var environment: Environment
var white_balance = preload("res://white_balance.gd").new()
var lens_effects = preload("res://lens_effects.gd").new()
var fog_effect = preload("res://fog_effect.gd").new()
var auto_exposure = preload("res://auto_exposure.gd").new()
var sun_elevation_deg := 0.0
# The sun's colour (linear sRGB, luminance 1): from the clear-sky model (sun_model.gd)
# unless --sun-kelvin is given. --sun-lux or the weather's sun.illuminance override the
# model's illuminance.
var sun_rgb := Vector3.ONE
var _sun_lux_given := false
var _sun_kelvin_given := false
var sun_azimuth_deg := 0.0
# The clear sky for the sun (sky_model.gd): luminous turbidity, zenith luminance (cd/m2),
# sky horizontal illuminance (lx), ground luminance (cd/m2).
var clear_sky := {}
# A test of the ambient light: a sky and ground of one luminance (cd/m2) everywhere
# (--sky-test-uniform=); 0 for the clear sky.
var sky_test_uniform_nits := 0.0

# Options (after --): --sun-time=ISO8601 with offset, --sun-lux=, --sun-kelvin=,
# --latitude=, --longitude=. Returns false for an option it does not know.
func parse_option(arg: String) -> bool:
	if arg.begins_with("--sun-time="):
		time_text = arg.trim_prefix("--sun-time=")
	elif arg.begins_with("--sun-lux="):
		sun_lux = arg.trim_prefix("--sun-lux=").to_float()
		_sun_lux_given = true
	elif arg.begins_with("--sun-kelvin="):
		sun_kelvin = arg.trim_prefix("--sun-kelvin=").to_float()
		_sun_kelvin_given = true
	elif arg.begins_with("--latitude="):
		latitude = arg.trim_prefix("--latitude=").to_float()
	elif arg.begins_with("--weather="):
		var text := FileAccess.get_file_as_string(arg.trim_prefix("--weather="))
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("weather file is not a JSON object: " + arg)
		else:
			weather = parsed
	elif arg.begins_with("--sky-test-uniform="):
		sky_test_uniform_nits = arg.trim_prefix("--sky-test-uniform=").to_float()
	elif arg.begins_with("--auto-exposure-speed="):
		auto_exposure_speed = arg.trim_prefix("--auto-exposure-speed=").to_float()
	elif arg.begins_with("--longitude="):
		longitude = arg.trim_prefix("--longitude=").to_float()
	else:
		return false
	return true

func add_to(world: Node3D) -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	var position := _sun_position()
	sun_elevation_deg = position.x
	sun_azimuth_deg = position.y
	# The sun's illuminance and colour come from its elevation (or the weather), so the
	# light is set after them.
	_apply_sun_weather()
	_set_sun_colour(sun)
	current_sun_lux = sun_lux
	var toward_sun := _direction(sun_azimuth_deg, sun_elevation_deg)
	world.add_child(sun)
	# A light shines along its -Z: point -Z away from the sun.
	sun.look_at_from_position(Vector3.ZERO, -toward_sun, Vector3.UP if absf(toward_sun.y) < 0.999 else Vector3.FORWARD)

	var sky := Sky.new()
	# The sky's uniforms change with the light (scale_light, later the time of day). Godot
	# would then rebuild the radiance map (ambient and reflections) over several frames
	# (INCREMENTAL, measured: 10 frames late); QUALITY rebuilds it in the frame of the change.
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	# The CIE clear sky in cd/m2 (cie_sky.gdshader). Godot multiplies the sky's output by
	# the background intensity; the shader divides it out.
	sky_material = ShaderMaterial.new()
	sky_material.shader = preload("res://cie_sky.gdshader")
	sky.sky_material = sky_material
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.background_intensity = 1.0
	_set_sky("luminance_scale", 1.0 / environment.background_intensity)
	_set_sky("sun_direction", toward_sun)
	_apply_clear_sky()
	_update_sun_disk()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Linear until a profile asks for a tone map (apply_color).
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_apply_fog()
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)
	print("LIGHT time=%s sun_elevation_deg=%.2f sun_azimuth_deg=%.2f sun_lux=%.0f sun_kelvin=%.0f" % [
		time_text, sun_elevation_deg, sun_azimuth_deg, sun_lux, sun_kelvin])

# Fog from the meteorological visibility (OpenSCENARIO Fog visualRange, the WMO
# meteorological optical range): contrast falls to 5 % at that distance, so the
# extinction coefficient is beta = -ln(0.05) / V (about 3 / V). fog_effect.gd applies
# Koschmieder's law on linear values. RGB only: depth and segmentation stay.
const FOG_CONTRAST_THRESHOLD := 0.05
# The airlight: fog lit by the day's light, scattering it as a white diffuser,
# L = E_h / pi with E_h the horizontal illuminance: the direct sun (lux x sin elevation)
# plus the sky (the clear sky's horizontal illuminance).
var fog_airlight_nits := 0.0

func _apply_fog() -> void:
	# Godot's own fog stays off (fog_effect.gd composes the fog on linear values).
	environment.fog_enabled = false
	var fog: Dictionary = weather.get("fog", {})
	if not fog.has("visualRange"):
		fog_effect.beta = 0.0
		return
	var visual_range := float(fog["visualRange"])
	var horizontal_lux := sun_lux * maxf(0.0, sin(deg_to_rad(sun_elevation_deg))) + float(clear_sky["diffuse_horizontal_lux"])
	fog_airlight_nits = horizontal_lux / PI
	fog_effect.beta = -log(FOG_CONTRAST_THRESHOLD) / visual_range
	fog_effect.airlight_nits = fog_airlight_nits
	print("WEATHER fog visualRange=%.1f m beta=%.6f /m airlight=%.0f nits" % [visual_range, fog_effect.beta, fog_airlight_nits])

# The sun's colour on the daylight locus (color_temperature.gd), the same white the
# camera's white balance uses. Godot multiplies light_color by its own (Planckian)
# light_temperature colour, so that is divided out; the intensity is scaled so the
# illuminance (luminance Y) stays sun_lux.
func _set_sun_colour(sun: DirectionalLight3D) -> void:
	sun.light_temperature = 6500.0
	var wanted: Vector3 = sun_rgb
	var godot: Vector3 = ColorTemperature.godot_light_rgb(6500.0)
	var colour := Vector3(wanted.x / godot.x, wanted.y / godot.y, wanted.z / godot.z)
	var largest := maxf(colour.x, maxf(colour.y, colour.z))
	colour /= largest
	sun.light_color = Color(colour.x, colour.y, colour.z).linear_to_srgb()
	sun.light_intensity_lux = sun_lux * largest

# The weather's sun (OpenSCENARIO Sun: azimuth from north clockwise and elevation, in
# radians; illuminance in lx) replaces the computed position and illuminance; the
# clear-sky model gives the illuminance and colour otherwise (memo 027).
func _apply_sun_weather() -> void:
	var given: Dictionary = weather.get("sun", {})
	if given.has("azimuth"):
		sun_azimuth_deg = rad_to_deg(float(given["azimuth"]))
	if given.has("elevation"):
		sun_elevation_deg = rad_to_deg(float(given["elevation"]))
	var model := SunModel.direct_sun(sun_elevation_deg)
	if not _sun_lux_given:
		sun_lux = float(given.get("illuminance", model["illuminance"]))
	if _sun_kelvin_given:
		sun_rgb = ColorTemperature.white_rgb(sun_kelvin)
	else:
		sun_rgb = ColorTemperature.xy_to_rgb(model["xy"])
	print("SUN elevation_deg=%.2f azimuth_deg=%.2f lux=%.0f xy=%.4f,%.4f" % [sun_elevation_deg, sun_azimuth_deg, sun_lux, model["xy"].x, model["xy"].y])

# The sky for the sun's elevation and illuminance (sky_model.gd; memo 027): the zenith
# luminance and colour table of the CIE clear sky and the ground below the horizon, lit
# by the sun and the sky (its colour taken as the sun's).
func _apply_clear_sky() -> void:
	clear_sky = SkyModel.clear_sky(sun_elevation_deg, sun_lux)
	_set_sky("zenith_luminance", clear_sky["zenith_luminance"])
	_set_sky("ground_radiance", sun_rgb * float(clear_sky["ground_luminance"]))
	_set_sky("colour_table", SkyModel.colour_table(sun_elevation_deg))
	if sky_test_uniform_nits > 0.0:
		for name in ["gradation_a", "indicatrix_c", "indicatrix_e"]:
			_set_sky(name, 0.0)
		var white := Image.create(1, 1, false, Image.FORMAT_RGBF)
		white.fill(Color(1, 1, 1))
		_set_sky("colour_table", ImageTexture.create_from_image(white))
		_set_sky("zenith_luminance", sky_test_uniform_nits)
		_set_sky("ground_radiance", Vector3.ONE * sky_test_uniform_nits)
		print("SKY test uniform luminance=%.0f" % sky_test_uniform_nits)
		return
	print("SKY turbidity=%.3f zenith_luminance=%.0f diffuse_horizontal_lux=%.0f ground_luminance=%.0f" % [
		clear_sky["turbidity"], clear_sky["zenith_luminance"], clear_sky["diffuse_horizontal_lux"], clear_sky["ground_luminance"]])

func _update_sun_disk() -> void:
	var half := SUN_ANGULAR_DIAMETER / 2.0
	var solid_angle := TAU * (1.0 - cos(half))
	var luminance := current_sun_lux / solid_angle
	var radiance: Vector3 = sun_rgb * luminance
	_set_sky("sun_disk_radiance", radiance)
	_set_sky("sun_disk_radius", half)

# Any change of the sky's uniforms makes Godot rebuild the radiance map (with QUALITY,
# about 3 ms a frame, measured), so a uniform is set only when its value changes
# (the exposure and the pixel angle are set for every frame drawn).
func _set_sky(name: String, value: Variant) -> void:
	if sky_material.get_shader_parameter(name) != value:
		sky_material.set_shader_parameter(name, value)

# The angle of one pixel of the image being drawn (smooths the sun disk's edge).
func set_pixel_angle(focal_px: float) -> void:
	_set_sky("pixel_angle", 1.0 / focal_px)

# Physical exposure at Godot's defaults (ISO 100, f/16, 1/100 s: Sunny 16). The camera
# then takes its field of view from the focal length and its clip from frustum_near/far,
# so they are computed from the profile's horizontal field of view and clip.
static func make_camera_attributes() -> CameraAttributesPhysical:
	var attributes := CameraAttributesPhysical.new()
	attributes.auto_exposure_enabled = false
	return attributes

# spec.photometric.exposure of the profile. Without it (or for a value it leaves out)
# the camera stays at Sunny 16: ISO 100, f/16, 1/100 s, manual.
# Godot's exposure_shutter_speed is 1 / seconds (like CARLA's shutter_speed);
# the schema's shutter_speed_s is seconds.
const SUNNY16_ISO := 100.0
const SUNNY16_F_NUMBER := 16.0
const SUNNY16_SHUTTER_S := 0.01

func apply_exposure(attributes: CameraAttributesPhysical, exposure: Dictionary) -> void:
	var iso := float(exposure.get("iso", SUNNY16_ISO))
	var f_number := float(exposure.get("f_number", SUNNY16_F_NUMBER))
	var shutter_s := float(exposure.get("shutter_speed_s", SUNNY16_SHUTTER_S))
	var auto := not exposure.is_empty() and String(exposure.get("mode", "auto")) == "auto"
	var compensation := float(exposure.get("compensation_ev", 0.0))
	# In auto mode the camera draws at the base exposure (iso, f-number, shutter) and
	# auto_exposure.gd adds the metered exposure (with the compensation) as a gain.
	var multiplier := 1.0 if auto else pow(2.0, compensation)
	attributes.exposure_sensitivity = iso
	attributes.exposure_aperture = f_number
	attributes.exposure_shutter_speed = 1.0 / shutter_s
	attributes.exposure_multiplier = multiplier
	# Godot's exposure normalization is multiplier / (1.2 x 2^EV100).
	var normalization := multiplier / (1.2 * pow(2.0, _ev100(iso, f_number, shutter_s)))
	_set_sky("cubemap_scale", 1.0 / normalization)
	fog_effect.exposure_normalization = normalization
	lens_effects.exposure_normalization = normalization
	# The schema's default mode is auto, but only when the profile has an exposure block.
	# Godot's auto exposure is not used: it meters the mean luminance, so a few sun
	# pixels set the exposure (memo 027); auto_exposure.gd meters a histogram.
	attributes.auto_exposure_enabled = false
	auto_exposure.enabled = auto
	auto_exposure.base_ev100 = _ev100(iso, f_number, shutter_s)
	auto_exposure.compensation_ev = compensation
	var metering: Dictionary = exposure.get("metering", {})
	auto_exposure.low_percentile = float(metering.get("low_percentile", 10.0))
	auto_exposure.high_percentile = float(metering.get("high_percentile", 90.0))
	auto_exposure.speed_stops_per_s = float(exposure.get("adaptation_speed", auto_exposure_speed))
	auto_exposure.ev100_min = float(exposure.get("ev100_min", -4.0))
	auto_exposure.ev100_max = float(exposure.get("ev100_max", 22.0))

# Scale all daylight by factor during a run (a test of the auto exposure's time response).
func scale_light(factor: float) -> void:
	sun.light_intensity_lux *= factor
	current_sun_lux *= factor
	for key in ["zenith_luminance", "diffuse_horizontal_lux", "ground_luminance"]:
		clear_sky[key] = float(clear_sky[key]) * factor
	_set_sky("zenith_luminance", clear_sky["zenith_luminance"])
	_set_sky("ground_radiance", sun_rgb * float(clear_sky["ground_luminance"]))
	_update_sun_disk()
	print("LIGHT scaled factor=%.4f sun_lux=%.0f zenith_luminance=%.0f" % [factor, sun.light_intensity_lux, clear_sky["zenith_luminance"]])

# Exposure value at ISO 100: log2(N^2 / t x 100 / S).
static func _ev100(iso: float, f_number: float, shutter_s: float) -> float:
	return log(f_number * f_number / shutter_s * 100.0 / iso) / log(2.0)

# The camera's colour processing, in Godot's order (memo 024 step 3):
#   exposure -> white balance (compositor effect, linear) -> [auto exposure, glow]
#   -> tone map -> output encoding (sRGB, or the profile's gamma through the colour
#   correction table).
# Without photometric settings: linear tone map, no white balance, sRGB output.
const TONE_MAPS := {
	"linear": Environment.TONE_MAPPER_LINEAR,
	"aces": Environment.TONE_MAPPER_ACES,
	"agx": Environment.TONE_MAPPER_AGX,
	"filmic": Environment.TONE_MAPPER_FILMIC,
}
# Scene value that the ACES and filmic curves map to 1 (Godot divides the curve by its
# value here). Godot's default 1.0 clips everything above 1 like the linear curve, so
# no highlight roll-off; AgX has its own white (tonemap_agx_white, 16.29 = Blender's).
# The same white for all three keeps about 4 stops above a white surface in the curve.
const TONE_MAP_WHITE := 16.29
const GAMMA_TABLE_SIZE := 1024
var _gamma_tables := {}

func attach_to(camera: Camera3D) -> void:
	var compositor := Compositor.new()
	# Lens effects first (they happen in the lens), then white balance (the sensor).
	# The atmosphere (fog), then the lens, then the sensor (white balance): the order light
	# meets them.
	# Metering (auto exposure) sees what reaches the sensor, after the lens.
	compositor.compositor_effects = [fog_effect, lens_effects, auto_exposure, white_balance]
	camera.compositor = compositor

func apply_color(photometric: Dictionary) -> void:
	var effects: Dictionary = photometric.get("effects", {})
	lens_effects.set_effects(effects)
	# Bloom: Godot's glow on scene values above 1, added before the tone map
	# (additive blend; the default soft light blends after the tone map).
	var bloom := float(effects.get("bloom", 0.0))
	environment.glow_enabled = bloom > 0.0
	environment.glow_intensity = bloom
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.tonemap_mode = TONE_MAPS.get(String(photometric.get("tone_map", "linear")), Environment.TONE_MAPPER_LINEAR)
	environment.tonemap_white = TONE_MAP_WHITE
	var balance: Dictionary = photometric.get("white_balance", {})
	white_balance.set_white_balance(float(balance.get("temperature_k", 6500.0)), float(balance.get("tint", 0.0)))
	if photometric.has("gamma"):
		environment.adjustment_enabled = true
		environment.adjustment_color_correction = _gamma_table(float(photometric["gamma"]))
	else:
		environment.adjustment_enabled = false
		environment.adjustment_color_correction = null

# Godot encodes the tone-mapped value as sRGB and then looks it up in the colour
# correction table, whose output is the final pixel. To get value^(1 / gamma) instead
# of sRGB, the table decodes sRGB and applies the power (no second encoding).
func _gamma_table(gamma: float) -> Texture2D:
	if _gamma_tables.has(gamma):
		return _gamma_tables[gamma]
	var data := PackedFloat32Array()
	for i in GAMMA_TABLE_SIZE:
		var encoded := float(i) / (GAMMA_TABLE_SIZE - 1)
		var linear := encoded / 12.92 if encoded <= 0.04045 else pow((encoded + 0.055) / 1.055, 2.4)
		var value := pow(linear, 1.0 / gamma)
		data.append_array([value, value, value])
	var image := Image.create_from_data(GAMMA_TABLE_SIZE, 1, false, Image.FORMAT_RGBF, data.to_byte_array())
	var texture := ImageTexture.create_from_image(image)
	_gamma_tables[gamma] = texture
	return texture

static func apply_lens(attributes: CameraAttributesPhysical, horizontal_fov_rad: float, near: float, far: float) -> void:
	attributes.frustum_focal_length = HALF_SENSOR_MM / tan(horizontal_fov_rad * 0.5)
	attributes.frustum_near = near
	attributes.frustum_far = far

# A test chart (memo 024): patches of known reflectance on a matte board, placed in the
# ROS world frame (x forward/North, y left/West, z up) facing yaw_deg. Albedo is set from
# linear reflectance (Godot's albedo colour is sRGB-encoded).
const CHART_PATCHES := [
	["white", Color(0.90, 0.90, 0.90)],
	["grey18", Color(0.18, 0.18, 0.18)],
	["black", Color(0.031, 0.031, 0.031)],
	# ColorChecker dark skin, blue sky, foliage, red, green, blue (linear sRGB, approx.)
	["dark_skin", Color(0.175, 0.080, 0.056)],
	["blue_sky", Color(0.123, 0.195, 0.333)],
	["foliage", Color(0.090, 0.150, 0.054)],
	["red", Color(0.396, 0.034, 0.042)],
	["green", Color(0.074, 0.290, 0.068)],
	["blue", Color(0.034, 0.046, 0.296)],
]
const PATCH_SIZE := 0.5

# An optional 5th value scales the chart (to keep its apparent size at a distance); an
# optional 6th tilts it back by that many degrees (90: facing up, to measure the light
# on a horizontal surface).
static func add_test_chart(world: Node3D, ros_pose: PackedFloat64Array) -> void:
	var chart := Node3D.new()
	var scale_factor := ros_pose[4] if ros_pose.size() > 4 else 1.0
	var tilt := ros_pose[5] if ros_pose.size() > 5 else 0.0
	chart.name = "TestChart"
	# ROS (x, y, z) -> Godot (-y, z, -x); ROS yaw (from North, counter-clockwise) -> rotation about Godot Y.
	chart.position = Vector3(-ros_pose[1], ros_pose[2], -ros_pose[0])
	chart.rotation = Vector3(-deg_to_rad(tilt), deg_to_rad(ros_pose[3]), 0)
	world.add_child(chart)
	# The board faces the chart's local +Z (Godot); patches in a 3 x 3 grid.
	for i in CHART_PATCHES.size():
		var patch := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(PATCH_SIZE, PATCH_SIZE) * scale_factor
		patch.mesh = quad
		var material := StandardMaterial3D.new()
		material.albedo_color = (CHART_PATCHES[i][1] as Color).linear_to_srgb()
		material.roughness = 1.0
		material.metallic = 0.0
		material.metallic_specular = 0.0
		# Lambertian (Godot's default Burley is about 8 % brighter here; memo 027).
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
		patch.material_override = material
		patch.position = Vector3((i % 3 - 1) * PATCH_SIZE * scale_factor, (1 - i / 3) * PATCH_SIZE * scale_factor, 0)
		patch.name = CHART_PATCHES[i][0]
		chart.add_child(patch)

# A checkerboard for camera calibration (memo 025): cols x rows squares of square_m,
# unshaded (black and white whatever the light), placed in the ROS world frame
# (x forward/North, y left/West, z up) with yaw, pitch and roll in degrees; the board
# faces its local +Z (Godot), i.e. the camera when yaw, pitch and roll are 0 and the
# camera looks north. OpenCV finds (cols - 1) x (rows - 1) inner corners.
static func add_test_board(world: Node3D, pose: PackedFloat64Array) -> void:
	var cols := int(pose[6])
	var rows := int(pose[7])
	var square := pose[8]
	var board := Node3D.new()
	board.name = "TestBoard"
	board.position = Vector3(-pose[1], pose[2], -pose[0])
	board.rotation = Vector3(deg_to_rad(pose[4]), deg_to_rad(pose[3]), deg_to_rad(pose[5]))
	world.add_child(board)
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(1, 1, 1)
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color(0, 0, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(square, square)
	# A white border of one square around the pattern helps the corner detector.
	for row in range(-1, rows + 1):
		for col in range(-1, cols + 1):
			var cell := MeshInstance3D.new()
			cell.mesh = quad
			var inside := row >= 0 and row < rows and col >= 0 and col < cols
			cell.material_override = black if inside and (row + col) % 2 == 0 else white
			cell.position = Vector3((col - (cols - 1) / 2.0) * square, ((rows - 1) / 2.0 - row) * square, 0.0)
			board.add_child(cell)

# Unit vector toward the sun in the Godot frame (azimuth from North, clockwise).
static func _direction(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var a := deg_to_rad(azimuth_deg)
	var e := deg_to_rad(elevation_deg)
	return Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e))

# Solar elevation and azimuth (degrees) for time_text at latitude/longitude
# (NOAA general solar position, accurate to a fraction of a degree).
func _sun_position() -> Vector2:
	var parts := _parse_time(time_text)
	var day_of_year: int = parts["day_of_year"]
	var hours_utc: float = parts["hours_utc"]
	var days_in_year := 366.0 if parts["leap"] else 365.0
	var gamma := TAU / days_in_year * (day_of_year - 1 + (hours_utc - 12.0) / 24.0)
	var equation_of_time := 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
		- 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
	var declination := (0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
		- 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
		- 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma))
	var solar_minutes := hours_utc * 60.0 + equation_of_time + 4.0 * longitude
	var hour_angle := deg_to_rad(solar_minutes / 4.0 - 180.0)
	var phi := deg_to_rad(latitude)
	var cos_zenith := sin(phi) * sin(declination) + cos(phi) * cos(declination) * cos(hour_angle)
	var zenith := acos(clampf(cos_zenith, -1.0, 1.0))
	var azimuth := atan2(sin(hour_angle), cos(hour_angle) * sin(phi) - tan(declination) * cos(phi)) + PI
	return Vector2(90.0 - rad_to_deg(zenith), fposmod(rad_to_deg(azimuth), 360.0))

# "YYYY-MM-DDTHH:MM:SS+HH:MM" (or Z) -> day of year and hours in UTC.
static func _parse_time(text: String) -> Dictionary:
	var date_time := text.split("T")
	var date := date_time[0].split("-")
	var rest := date_time[1]
	var offset_hours := 0.0
	var clock := rest
	if rest.ends_with("Z"):
		clock = rest.trim_suffix("Z")
	else:
		var sign_at := maxi(rest.rfind("+"), rest.rfind("-"))
		if sign_at > 0:
			var offset := rest.substr(sign_at + 1).split(":")
			offset_hours = offset[0].to_float() + (offset[1].to_float() / 60.0 if offset.size() > 1 else 0.0)
			if rest[sign_at] == "-":
				offset_hours = -offset_hours
			clock = rest.substr(0, sign_at)
	var hms := clock.split(":")
	var year := date[0].to_int()
	var month := date[1].to_int()
	var day := date[2].to_int()
	var leap := (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
	var month_days := [31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var day_of_year := day
	for m in range(month - 1):
		day_of_year += month_days[m]
	var hours := hms[0].to_float() + hms[1].to_float() / 60.0 + (hms[2].to_float() / 3600.0 if hms.size() > 2 else 0.0)
	var hours_utc := hours - offset_hours
	# Crossing midnight in UTC moves the day.
	if hours_utc < 0:
		hours_utc += 24.0
		day_of_year -= 1
	elif hours_utc >= 24:
		hours_utc -= 24.0
		day_of_year += 1
	return {"day_of_year": day_of_year, "hours_utc": hours_utc, "leap": leap}
