extends SceneTree

const Lens = preload("res://lens.gd")

var failures := 0


func _init() -> void:
	var file := FileAccess.open("res://tests/lens_vectors.json", FileAccess.READ)
	check(file != null, "reference vectors can be opened")
	if file != null:
		var vectors = JSON.parse_string(file.get_as_text())
		check(vectors is Dictionary, "reference vectors are JSON dictionary")
		if vectors is Dictionary:
			for case in vectors["source_cases"]:
				test_case(case)
			test_cube(vectors["cube"])
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


func vector3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func test_cube(case: Dictionary) -> void:
	var lens = Lens.new()
	check(lens.load_spec(case["spec"]), "cube lens spec loads")
	check(lens.compute_views(), "cube views compute")
	check(lens.cube, "wide lens uses cube")
	check(lens.cube_face_names.size() == case["names"].size(), "cube face count")
	for i in mini(lens.cube_face_names.size(), case["names"].size()):
		check(lens.cube_face_names[i] == String(case["names"][i]), "cube face name %d" % i)
	check(lens.cube_size == int(case["size"]), "cube size")
	check_near(lens.cube_focal, float(case["focal"]), 1e-9, "cube focal")
	for item in case["face_cases"]:
		check(Lens.face_of(vector3(item[0])) == String(item[1]), "face_of %s" % [item[0]])
	for name in case["faces"]:
		var face: Array = case["faces"][name]
		var basis := Lens.face_basis(name)
		var xf := vector3(face[0])
		var yf := vector3(face[1])
		var zf := vector3(face[2])
		var to_godot := func(v: Vector3) -> Vector3: return Vector3(v.x, -v.y, -v.z)
		check(basis.x.is_equal_approx(to_godot.call(xf)), "face basis x %s" % name)
		check(basis.y.is_equal_approx(to_godot.call(-yf)), "face basis y %s" % name)
		check(basis.z.is_equal_approx(to_godot.call(-zf)), "face basis z %s" % name)
