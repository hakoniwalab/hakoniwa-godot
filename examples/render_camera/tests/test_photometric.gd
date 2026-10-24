extends SceneTree

const ColorTemperature = preload("res://color_temperature.gd")
const WhiteBalance = preload("res://white_balance.gd")
const Lighting = preload("res://lighting.gd")

var failures := 0


func _init() -> void:
	test_color_temperature()
	test_white_balance()
	test_exposure_value()
	test_sun_position()
	test_parse_time()
	if failures == 0:
		print("PHOTOMETRIC_TEST_OK")
	quit(failures)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual - expected) <= tolerance,
		"%s: got %.9f, expected %.9f +/- %.9f" % [message, actual, expected, tolerance])


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
