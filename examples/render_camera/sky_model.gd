extends RefCounted

# Clear-sky luminance and colour: a copy of hakoniwa-scenario
# hakoniwa_scenario/environment/sky.py (the reference, memo 027).
# Luminance: CIE standard general sky (ISO 15469) type 12, L / Lz = f(chi) phi(Z) / (f(Zs) phi(0)).
# Level: Darula and Kittler (eSim 2002) eq. (13), the zenith luminance from the sun's
# altitude and the luminous turbidity Tv, Tv from the direct sun (sun_model.gd).
# Colour: single scattering of the extraterrestrial sun by the same molecules and
# aerosol as the direct sun; only its chromaticity is used.
# Below the horizon: the ground, albedo GROUND_ALBEDO, L = rho (Pv sin h + Dv) / pi.

const SunModel = preload("res://sun_model.gd")
const ColorTemperature = preload("res://color_temperature.gd")

const GRADATION_A := -1.0
const GRADATION_B := -0.32
const INDICATRIX_C := 10.0
const INDICATRIX_D := -3.0
const INDICATRIX_E := 0.45
const ZENITH_A1 := 1.036
const ZENITH_A2 := 0.710
const ZENITH_C := 4.43
const ZENITH_D := 0.74
const SOLAR_ILLUMINANCE_CONSTANT_LUX := 133800.0
const GROUND_ALBEDO := 0.2
const AEROSOL_ASYMMETRY := 0.65
# The colour table: view zenith angle 0-90 deg by angle from the sun 0-180 deg.
const COLOUR_ZENITH_STEPS := 32
const COLOUR_SCATTER_STEPS := 64

static func gradation(zenith: float) -> float:
	if zenith >= PI / 2.0:
		return 1.0
	return 1.0 + GRADATION_A * exp(GRADATION_B / cos(zenith))

static func indicatrix(chi: float) -> float:
	return 1.0 + INDICATRIX_C * (exp(INDICATRIX_D * chi) - exp(INDICATRIX_D * PI / 2.0)) + INDICATRIX_E * pow(cos(chi), 2)

static func relative_luminance(zenith: float, azimuth: float, sun_zenith: float, sun_azimuth: float) -> float:
	var cos_chi := cos(sun_zenith) * cos(zenith) + sin(sun_zenith) * sin(zenith) * cos(azimuth - sun_azimuth)
	var chi := acos(clampf(cos_chi, -1.0, 1.0))
	return indicatrix(chi) * gradation(zenith) / (indicatrix(sun_zenith) * gradation(0.0))

static func luminous_turbidity(elevation_deg: float, direct_normal_lux: float) -> float:
	var m := SunModel.air_mass(elevation_deg)
	var av := 1.0 / (9.9 + 0.043 * m)
	return -log(direct_normal_lux / SOLAR_ILLUMINANCE_CONSTANT_LUX) / (av * m)

# cd/m2
static func zenith_luminance(elevation_deg: float, turbidity: float) -> float:
	var h := deg_to_rad(elevation_deg)
	var a := ZENITH_A1 * turbidity + ZENITH_A2
	var kcd := a * sin(h) + 0.7 * (turbidity + 1.0) * pow(sin(h), ZENITH_C) / pow(cos(h), ZENITH_D) + 0.04 * turbidity
	return kcd * 1000.0

# Lz / Dv by integrating the relative luminance times cos Z over the sky.
static func zenith_over_diffuse(elevation_deg: float, steps := 180) -> float:
	var sun_zenith := deg_to_rad(90.0 - elevation_deg)
	var dz := (PI / 2.0) / steps
	var da := TAU / (2 * steps)
	var total := 0.0
	for i in steps:
		var z := (i + 0.5) * dz
		var ring := 0.0
		for j in 2 * steps:
			ring += relative_luminance(z, (j + 0.5) * da, sun_zenith, 0.0)
		total += ring * da * sin(z) * cos(z) * dz
	return 1.0 / total

# The sun's direct normal illuminance (lx) gives Tv; returns Tv, the zenith luminance,
# the sky (diffuse) horizontal illuminance and the ground luminance.
static func clear_sky(elevation_deg: float, direct_normal_lux: float) -> Dictionary:
	if elevation_deg <= 0.0 or direct_normal_lux <= 0.0:
		return {"turbidity": NAN, "zenith_luminance": 0.0, "diffuse_horizontal_lux": 0.0, "ground_luminance": 0.0}
	var turbidity := luminous_turbidity(elevation_deg, direct_normal_lux)
	var lz := zenith_luminance(elevation_deg, turbidity)
	var dv := lz / zenith_over_diffuse(elevation_deg)
	var direct_horizontal := direct_normal_lux * sin(deg_to_rad(elevation_deg))
	return {"turbidity": turbidity, "zenith_luminance": lz, "diffuse_horizontal_lux": dv,
		"ground_luminance": GROUND_ALBEDO * (direct_horizontal + dv) / PI}

static func _henyey_greenstein(cos_theta: float, g: float) -> float:
	return (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * cos_theta, 1.5)

static func chromaticity(view_zenith: float, cos_scatter: float, elevation_deg: float) -> Vector2:
	var m_s := SunModel.air_mass(elevation_deg)
	var m_v := SunModel.air_mass(90.0 - rad_to_deg(view_zenith))
	var rayleigh_phase := 0.75 * (1.0 + cos_scatter * cos_scatter)
	var aerosol_phase := _henyey_greenstein(cos_scatter, AEROSOL_ASYMMETRY)
	var total := Vector3.ZERO
	for wl in range(380, 781, 5):
		var um := wl / 1000.0
		var tau_r := 0.008735 * pow(um, -4.08)
		var tau_a := SunModel.ANGSTROM_BETA * pow(um, -SunModel.ANGSTROM_ALPHA)
		var tau := tau_r + tau_a
		var path: float
		if absf(m_v - m_s) < 1e-6:
			path = tau * m_s * exp(-tau * m_s)
		else:
			path = m_v / (m_v - m_s) * (exp(-tau * m_s) - exp(-tau * m_v))
		var power := SunModel._planck(wl) * (tau_r * rayleigh_phase + tau_a * aerosol_phase) / tau * path
		total += SunModel.cie_xyz(wl) * power
	var sum := total.x + total.y + total.z
	return Vector2(total.x / sum, total.y / sum)

# The sky's colour (linear sRGB, luminance 1) by view zenith angle (u) and angle from
# the sun (v), at texel centres; for cie_sky.gdshader.
static func colour_table(elevation_deg: float) -> ImageTexture:
	var image := Image.create(COLOUR_SCATTER_STEPS, COLOUR_ZENITH_STEPS, false, Image.FORMAT_RGBF)
	for row in COLOUR_ZENITH_STEPS:
		var zenith := (row + 0.5) / COLOUR_ZENITH_STEPS * PI / 2.0
		for col in COLOUR_SCATTER_STEPS:
			var scatter := (col + 0.5) / COLOUR_SCATTER_STEPS * PI
			var rgb := ColorTemperature.xy_to_rgb(chromaticity(zenith, cos(scatter), elevation_deg))
			image.set_pixel(col, row, Color(rgb.x, rgb.y, rgb.z))
	return ImageTexture.create_from_image(image)
