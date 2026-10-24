extends SceneTree

const ColorTemperature = preload("res://color_temperature.gd")
const WhiteBalance = preload("res://white_balance.gd")
const Lighting = preload("res://lighting.gd")
const SunModel = preload("res://sun_model.gd")
const SkyModel = preload("res://sky_model.gd")
const AutoExposure = preload("res://auto_exposure.gd")

var failures := 0
var checks := 0
var max_reference_relative_difference := 0.0


func _init() -> void:
	test_color_temperature()
	test_white_balance()
	test_exposure_value()
	test_sun_position()
	test_parse_time()
	test_reference_vectors()
	if failures == 0:
		print("PHOTOMETRIC_CHECKS=%d" % checks)
		print("PHOTOMETRIC_MAX_REL_DIFF=" + String.num_scientific(max_reference_relative_difference))
		print("PHOTOMETRIC_TEST_OK")
	quit(failures)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual - expected) <= tolerance,
		"%s: got %.9f, expected %.9f +/- %.9f" % [message, actual, expected, tolerance])


func check_relative(actual: float, expected: float, tolerance: float, message: String) -> void:
	var scale := maxf(absf(expected), 1e-12)
	max_reference_relative_difference = maxf(max_reference_relative_difference, absf(actual - expected) / scale)
	check_near(actual, expected, tolerance * scale, message)


func check_vector_near(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	check_near(actual.x, expected.x, tolerance, message + " R")
	check_near(actual.y, expected.y, tolerance, message + " G")
	check_near(actual.z, expected.z, tolerance, message + " B")


func test_color_temperature() -> void:
	# CIE D65 is 6504 K and xy=(0.31271, 0.32902). The daylight-locus fit at
	# 6500 K therefore differs slightly; 0.002 in linear RGB covers that 4 K gap
	# and the rounded sRGB/XYZ matrix coefficients.
	check_vector_near(ColorTemperature.white_rgb(6500.0), Vector3.ONE, 0.002,
		"6500 K daylight white is D65")

	# xy_to_rgb constructs XYZ with Y=1. The IEC 61966-2-1 linear-sRGB luminance
	# coefficients used by luminance() recover Y, within rounded-matrix error.
	for temperature in [1667.0, 2000.0, 3999.0, 4000.0, 6500.0, 25000.0]:
		check_near(ColorTemperature.luminance(ColorTemperature.white_rgb(temperature)),
			1.0, 0.00025, "white luminance at %.0f K" % temperature)

	# The implementation changes from the Kim et al. (2002) Planckian cubic fit
	# to the CIE daylight locus at 4000 K. Adjacent 1 K samples should be continuous;
	# 0.04 is about 2.6% of the largest channel at this join.
	var below: Vector3 = ColorTemperature.white_rgb(3999.0)
	var above: Vector3 = ColorTemperature.white_rgb(4000.0)
	var join_delta := (below - above).abs()
	check(maxf(join_delta.x, maxf(join_delta.y, join_delta.z)) < 0.04,
		"4000 K locus join has no large jump")

	var godot_6500: Vector3 = ColorTemperature.godot_light_rgb(6500.0)
	check_near(maxf(godot_6500.x, maxf(godot_6500.y, godot_6500.z)),
		1.0, 0.000001, "Godot light RGB is max-normalized")
	check(godot_6500.y < godot_6500.x and godot_6500.y < godot_6500.z,
		"Godot 6500 K Planckian green is below red and blue")
	check_near(godot_6500.y, 0.94, 0.02, "Godot 6500 K green is about 6% low (memo 024)")
	check(ColorTemperature.white_rgb(3000.0).x / ColorTemperature.white_rgb(3000.0).z
		> ColorTemperature.white_rgb(6500.0).x / ColorTemperature.white_rgb(6500.0).z,
		"lower colour temperature has larger R/B")


func test_white_balance() -> void:
	check(WhiteBalance.gains_for(6500.0, 0.0) == Vector3.ONE,
		"6500 K zero-tint gains are exactly one")
	var reference: Vector3 = ColorTemperature.white_rgb(6500.0)
	for temperature in [2000.0, 4000.0, 5800.0, 9000.0, 25000.0]:
		var balanced: Vector3 = ColorTemperature.white_rgb(temperature) * WhiteBalance.gains_for(temperature, 0.0)
		check_vector_near(balanced, reference, 0.000001,
			"white balance neutralizes %.0f K light" % temperature)
	# Positive tint describes magenta light; compensating it raises the green gain
	# (the picture turns greener, like UE's WhiteTint; memo 024).
	var neutral_green: float = WhiteBalance.gains_for(6500.0, 0.0).y
	var positive_green: float = WhiteBalance.gains_for(6500.0, 0.1).y
	check(positive_green > neutral_green,
		"positive tint raises the green gain: got %.9f, neutral %.9f" % [positive_green, neutral_green])


func test_exposure_value() -> void:
	var base: float = Lighting._ev100(100.0, 16.0, 0.01)
	check_near(base, log(25600.0) / log(2.0), 0.000001, "Sunny 16 EV100")
	check_near(Lighting._ev100(200.0, 16.0, 0.01), base - 1.0, 0.000001, "double ISO is -1 EV")
	check_near(Lighting._ev100(100.0, 16.0, 0.02), base - 1.0, 0.000001, "double shutter time is -1 EV")
	check_near(Lighting._ev100(100.0, 16.0 * sqrt(2.0), 0.01), base + 1.0, 0.000001,
		"aperture times sqrt(2) is +1 EV")


func test_sun_position() -> void:
	var lighting = Lighting.new()
	var position: Vector2 = lighting._sun_position()
	check_near(position.x, 42.25, 0.2, "Tocho recorded sun elevation")
	check_near(position.y, 191.5, 0.2, "Tocho recorded sun azimuth")

	# NOAA Solar Calculator example: 2003-10-17 12:30:30, UTC-07:00,
	# 39.742476 N, 105.1786 W gives elevation 40.02 deg and azimuth 194.34 deg.
	# Source: NOAA Global Monitoring Laboratory, Solar Calculation Details,
	# https://gml.noaa.gov/grad/solcalc/calcdetails.html
	lighting.latitude = 39.742476
	lighting.longitude = -105.1786
	lighting.time_text = "2003-10-17T12:30:30-07:00"
	position = lighting._sun_position()
	check_near(position.x, 40.02, 0.2, "NOAA example sun elevation")
	check_near(position.y, 194.34, 0.2, "NOAA example sun azimuth")


func test_parse_time() -> void:
	check_parsed_time("2026-10-24T03:15:00Z", 297, 3.25, "Z")
	check_parsed_time("2026-10-24T12:00:00+09:00", 297, 3.0, "+09:00")
	check_parsed_time("2026-10-24T12:00:00-05:00", 297, 17.0, "-05:00")
	check_parsed_time("2026-10-24T02:00:00+09:00", 296, 17.0, "previous UTC date")
	check_parsed_time("2026-10-24T23:00:00-05:00", 298, 4.0, "next UTC date")


func check_parsed_time(text: String, expected_day: int, expected_hour: float, message: String) -> void:
	var parsed: Dictionary = Lighting._parse_time(text)
	check(parsed["day_of_year"] == expected_day,
		"%s day: got %s, expected %d" % [message, parsed["day_of_year"], expected_day])
	check_near(parsed["hours_utc"], expected_hour, 0.000001, message + " hour")


func test_reference_vectors() -> void:
	var file := FileAccess.open("res://tests/photometric_vectors.json", FileAccess.READ)
	check(file != null, "open photometric_vectors.json")
	if file == null:
		return
	var vectors = JSON.parse_string(file.get_as_text())
	check(vectors is Dictionary, "parse photometric_vectors.json")
	if not vectors is Dictionary:
		return
	for case in vectors["sun"]:
		var actual: Dictionary = SunModel.direct_sun(case["elevation"])
		check_relative(actual["illuminance"], case["illuminance"], 1e-6, "sun illuminance %.2f" % case["elevation"])
		check_relative(actual["xy"].x, case["xy"][0], 1e-6, "sun x %.2f" % case["elevation"])
		check_relative(actual["xy"].y, case["xy"][1], 1e-6, "sun y %.2f" % case["elevation"])
	for case in vectors["clear_sky"]:
		var actual: Dictionary = SkyModel.clear_sky(case["elevation"], case["direct_normal_lux"])
		for key in ["turbidity", "zenith_luminance", "diffuse_horizontal_lux", "ground_luminance"]:
			check_relative(actual[key], case[key], 1e-6, "clear sky %s %.2f" % [key, case["elevation"]])
	for case in vectors["relative_luminance"]:
		var actual := SkyModel.relative_luminance(case["zenith"], case["azimuth"], case["sun_zenith"], case["sun_azimuth"])
		check_relative(actual, case["expected"], 1e-6, "relative luminance")
	for case in vectors["chromaticity"]:
		var actual := SkyModel.chromaticity(case["view_zenith"], case["cos_scatter"], case["elevation"])
		check_relative(actual.x, case["xy"][0], 1e-6, "sky chromaticity x")
		check_relative(actual.y, case["xy"][1], 1e-6, "sky chromaticity y")
	for case in vectors["metered_log2"]:
		var counts := PackedInt32Array(case["counts"])
		check_relative(AutoExposure.metered_log2(counts, case["low"], case["high"]), case["expected"], 1e-6, "metered log2")
	for case in vectors["target_ev100"]:
		var actual := AutoExposure.target_ev100(case["metered"], case["compensation"], case["low"], case["high"])
		check_relative(actual, case["expected"], 1e-6, "target EV100")
	for case in vectors["adapt"]:
		var actual := AutoExposure.adapt(case["current"], case["target"], case["speed"], case["dt"])
		check_relative(actual, case["expected"], 1e-6, "exposure adaptation")
