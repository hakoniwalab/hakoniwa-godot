extends SceneTree

const Lens = preload("res://lens.gd")

var failures := 0


func _init() -> void:
	var file := FileAccess.open("res://tests/lens_vectors.json", FileAccess.READ)
	check(file != null, "reference vectors can be opened")
	if file != null:
		var cases = JSON.parse_string(file.get_as_text())
		check(cases is Array, "reference vectors are JSON array")
		if cases is Array:
			for case in cases:
				test_case(case)
	if failures == 0:
		print("LENS_TEST_OK")
	quit(failures)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual - expected) <= tolerance,
		"%s: got %.9f, expected %.9f +/- %.9f" % [message, actual, expected, tolerance])


func test_case(case: Dictionary) -> void:
	var lens = Lens.new()
	check(lens.load_spec(case["spec"]), "lens spec loads")
	check(lens.compute_source(), "source camera computes")
	var expected_source: Array = case["source"]
	check(lens.source_width == int(expected_source[0]), "source width")
	check(lens.source_height == int(expected_source[1]), "source height")
	check_near(lens.source_focal, float(expected_source[2]), 1e-9, "source focal")
	for sample in case["samples"]:
		var pixel: Array = sample["pixel"]
		var expected: Array = sample["ray"]
		var actual: Vector3 = lens.pixel_to_ray(float(pixel[0]), float(pixel[1]))
		check_near(actual.x, float(expected[0]), 1e-6, "ray x")
		check_near(actual.y, float(expected[1]), 1e-6, "ray y")
		check_near(actual.z, float(expected[2]), 1e-6, "ray z")
