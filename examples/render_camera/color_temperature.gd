extends RefCounted

# Colour of white light from a colour temperature, in linear sRGB (D65 white = 1, 1, 1).
# Used for the sun's colour and the camera's white balance (hakoniwa-scenario memo 024),
# so both mean the same white:
#   - 4000 K and above: the CIE daylight locus (D-series; D65 is about 6504 K), as UE's
#     (and so CARLA's) white balance does. Sunlight and skylight follow this locus.
#   - below 4000 K: the Planckian (blackbody) locus.
# Godot's own light_temperature uses the Planckian locus at every temperature
# (scene/3d/light_3d.cpp, _color_from_temperature), so its 6500 K is slightly magenta
# against D65 (green 6 % low, measured on a grey card).

const SRGB_FROM_XYZ := [
	Vector3(3.2404542, -1.5371385, -0.4985314),
	Vector3(-0.9692660, 1.8760108, 0.0415560),
	Vector3(0.0556434, -0.2040259, 1.0572252),
]

# Linear sRGB of a white of luminance Y = 1.
static func white_rgb(temperature_k: float, tint := 0.0, tint_uv_scale := 0.05) -> Vector3:
	var t := clampf(temperature_k, 1667.0, 25000.0)
	var xy := daylight_xy(t) if t >= 4000.0 else planckian_xy(t)
	if tint != 0.0:
		xy = _apply_tint(xy, t, tint, tint_uv_scale)
	return xy_to_rgb(xy)

# Godot's Light3D colour for light_temperature (Planckian, Krystek's CIE 1960 fit,
# divided by its largest channel), linear sRGB.
static func godot_light_rgb(temperature_k: float) -> Vector3:
	var t := temperature_k
	var t2 := t * t
	var u := (0.860117757 + 1.54118254e-4 * t + 1.28641212e-7 * t2) / (1.0 + 8.42420235e-4 * t + 7.08145163e-7 * t2)
	var v := (0.317398726 + 4.22806245e-5 * t + 4.20481691e-8 * t2) / (1.0 - 2.89741816e-5 * t + 1.61456053e-7 * t2)
	var d := 1.0 / (2.0 * u - 8.0 * v + 4.0)
	var rgb := xy_to_rgb(Vector2(3.0 * u * d, 2.0 * v * d))
	return (rgb / maxf(rgb.x, maxf(rgb.y, rgb.z))).clamp(Vector3.ZERO, Vector3.ONE)

static func luminance(rgb: Vector3) -> float:
	return 0.2126 * rgb.x + 0.7152 * rgb.y + 0.0722 * rgb.z

static func xy_to_rgb(xy: Vector2) -> Vector3:
	var xyz := Vector3(xy.x / xy.y, 1.0, (1.0 - xy.x - xy.y) / xy.y)
	return Vector3(SRGB_FROM_XYZ[0].dot(xyz), SRGB_FROM_XYZ[1].dot(xyz), SRGB_FROM_XYZ[2].dot(xyz))

# CIE daylight locus (4000-25000 K).
static func daylight_xy(t: float) -> Vector2:
	var x: float
	if t <= 7000.0:
		x = -4.6070e9 / (t * t * t) + 2.9678e6 / (t * t) + 0.09911e3 / t + 0.244063
	else:
		x = -2.0064e9 / (t * t * t) + 1.9018e6 / (t * t) + 0.24748e3 / t + 0.237040
	return Vector2(x, -3.000 * x * x + 2.870 * x - 0.275)

# Planckian locus in CIE xy (Kim et al. 2002 cubic fit, 1667-25000 K).
static func planckian_xy(t: float) -> Vector2:
	var x: float
	if t <= 4000.0:
		x = -0.2661239e9 / (t * t * t) - 0.2343589e6 / (t * t) + 0.8776956e3 / t + 0.179910
	else:
		x = -3.0258469e9 / (t * t * t) + 2.1070379e6 / (t * t) + 0.2226347e3 / t + 0.240390
	var y: float
	if t <= 2222.0:
		y = -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683
	elif t <= 4000.0:
		y = -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867
	else:
		y = 3.0817580 * x * x * x - 5.87338670 * x * x + 3.75112997 * x - 0.37001483
	return Vector2(x, y)

# Move the white point across the Planckian locus in CIE 1960 uv: positive tint
# toward magenta (smaller v), negative toward green.
static func _apply_tint(xy: Vector2, t: float, tint: float, scale: float) -> Vector2:
	var along := (_xy_to_uv(planckian_xy(clampf(t * 1.01, 1667.0, 25000.0))) - _xy_to_uv(planckian_xy(t))).normalized()
	var normal := Vector2(-along.y, along.x)
	if normal.y > 0.0:
		normal = -normal
	var uv := _xy_to_uv(xy) + normal * tint * scale
	var d := 2.0 * uv.x - 8.0 * uv.y + 4.0
	return Vector2(3.0 * uv.x / d, 2.0 * uv.y / d)

static func _xy_to_uv(xy: Vector2) -> Vector2:
	var d := -2.0 * xy.x + 12.0 * xy.y + 3.0
	return Vector2(4.0 * xy.x / d, 6.0 * xy.y / d)
