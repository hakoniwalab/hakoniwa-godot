extends RefCounted

# Direct sunlight at the ground for a clear sky: a copy of hakoniwa-scenario
# hakoniwa_scenario/environment/sun.py (the reference, memo 027). A 5778 K blackbody
# scaled to 127,500 lx outside the atmosphere, attenuated per wavelength by
# exp(-m tau): m the air mass (Kasten and Young 1989), tau Rayleigh plus aerosol
# (Angstrom beta 0.05, alpha 1.3). Illuminance and CIE 1931 xy come from the result.

const EXTRATERRESTRIAL_LUX := 127500.0
const SUN_TEMPERATURE_K := 5778.0
const ANGSTROM_BETA := 0.05
const ANGSTROM_ALPHA := 1.3

static func air_mass(elevation_deg: float) -> float:
	if elevation_deg <= -0.5:
		return INF
	return 1.0 / (sin(deg_to_rad(elevation_deg)) + 0.50572 * pow(elevation_deg + 6.07995, -1.6364))

static func optical_depth(wavelength_nm: float) -> float:
	var um := wavelength_nm / 1000.0
	return 0.008735 * pow(um, -4.08) + ANGSTROM_BETA * pow(um, -ANGSTROM_ALPHA)

static func _planck(wavelength_nm: float) -> float:
	var m := wavelength_nm * 1e-9
	return 1.0 / (pow(m, 5) * (exp(1.4387769e-2 / (m * SUN_TEMPERATURE_K)) - 1.0))

static func _g(x: float, mu: float, s1: float, s2: float) -> float:
	var s := s1 if x < mu else s2
	return exp(-0.5 * pow((x - mu) / s, 2))

# CIE 1931 2 deg colour matching functions (Wyman, Sloan and Shirley 2013 fit).
static func cie_xyz(wl: float) -> Vector3:
	var x := 1.056 * _g(wl, 599.8, 37.9, 31.0) + 0.362 * _g(wl, 442.0, 16.0, 26.7) - 0.065 * _g(wl, 501.1, 20.4, 26.2)
	var y := 0.821 * _g(wl, 568.8, 46.9, 40.5) + 0.286 * _g(wl, 530.9, 16.3, 31.1)
	var z := 1.217 * _g(wl, 437.0, 11.8, 36.0) + 0.681 * _g(wl, 459.0, 26.0, 13.8)
	return Vector3(x, y, z)

static func _xyz_after(m: float) -> Vector3:
	var total := Vector3.ZERO
	for wl in range(380, 781, 5):
		var transmission := exp(-m * optical_depth(wl)) if m > 0.0 else 1.0
		total += cie_xyz(wl) * (_planck(wl) * transmission)
	return total

# {"illuminance": lx (normal to the sun), "xy": Vector2}; illuminance 0 below the horizon.
static func direct_sun(elevation_deg: float) -> Dictionary:
	var m := air_mass(elevation_deg)
	if is_inf(m):
		return {"illuminance": 0.0, "xy": Vector2(0.3127, 0.3290)}
	var outside := _xyz_after(0.0)
	var ground := _xyz_after(m)
	var sum := ground.x + ground.y + ground.z
	return {"illuminance": EXTRATERRESTRIAL_LUX * ground.y / outside.y, "xy": Vector2(ground.x / sum, ground.y / sum)}
