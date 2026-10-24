extends RefCounted

# The camera lens model (spec.lens) in GDScript: a copy of hakoniwa-scenario
# hakoniwa_scenario/sensors/lens.py (memo 025), which is the reference; tests compare
# the two. The per-pixel copy is lens_warp.gdshader. Conventions as lens.py: pixel
# centres at integers (OpenCV / ROS), optical frame x right, y down, z forward.

const PROJECTION_IDS := {
	"perspective": 0, "equidistant": 1, "equisolid_angle": 2,
	"stereographic": 3, "orthographic": 4, "kannala_brandt": 5,
}
const MAX_SOURCE_ANGLE_RAD := deg_to_rad(75.0)
const ITERATIONS := 20
const RESIDUAL_LIMIT := 1e-6

var width := 0
var height := 0
var fx := 1.0
var fy := 1.0
var cx := 0.0
var cy := 0.0
var skew := 0.0
var projection := "perspective"
var distortion := "none"
var brown := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])  # k1, k2, p1, p2, k3
var kb := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])  # k0..k3
var cutoff_angle := PI
var error := ""
# The ideal pinhole image to draw first (source_camera).
var source_width := 0
var source_height := 0
var source_focal := 1.0

# From a parsed profile (spec). Sets error (and returns false) for an unsupported lens.
func load_spec(spec: Dictionary) -> bool:
	width = int(spec["image"]["width"])
	height = int(spec["image"]["height"])
	var lens: Dictionary = spec.get("lens", {})
	var intrinsics: Dictionary = lens.get("intrinsics", {})
	if not intrinsics.is_empty():
		fx = float(intrinsics["fx"])
		fy = float(intrinsics["fy"])
		cx = float(intrinsics["cx"])
		cy = float(intrinsics["cy"])
		skew = float(intrinsics.get("skew", 0.0))
	else:
		fx = width / 2.0 / tan(float(spec["horizontal_fov"]) / 2.0)
		fy = fx
		cx = (width - 1) / 2.0
		cy = (height - 1) / 2.0
	projection = String(lens.get("projection", "perspective"))
	var dist: Dictionary = lens.get("distortion", {})
	distortion = String(dist.get("model", "none"))
	if distortion == "brown_conrady" and projection != "perspective":
		error = "brown_conrady distortion needs the perspective projection"
		return false
	if distortion == "kannala_brandt" or projection == "kannala_brandt":
		projection = "kannala_brandt"
		distortion = "kannala_brandt"
	if dist.has("center"):
		error = "distortion.center is not supported; use intrinsics cx, cy"
		return false
	brown = PackedFloat64Array([float(dist.get("k1", 0.0)), float(dist.get("k2", 0.0)),
		float(dist.get("p1", 0.0)), float(dist.get("p2", 0.0)), float(dist.get("k3", 0.0))])
	var kb_values: Array = dist.get("kb", [0.0, 0.0, 0.0, 0.0])
	kb = PackedFloat64Array(kb_values)
	cutoff_angle = float(lens.get("cutoff_angle", PI))
	if not PROJECTION_IDS.has(projection):
		error = "unknown projection " + projection
		return false
	return true

# An undistorted perspective camera centred on the image: drawn directly, no warp.
func is_ideal() -> bool:
	return projection == "perspective" and distortion == "none" and skew == 0.0 and fx == fy \
		and cx == (width - 1) / 2.0 and cy == (height - 1) / 2.0 and cutoff_angle >= PI / 2.0

func _image_radius(theta: float) -> float:
	match projection:
		"perspective":
			return tan(theta)
		"equidistant":
			return theta
		"equisolid_angle":
			return 2.0 * sin(theta / 2.0)
		"stereographic":
			return 2.0 * tan(theta / 2.0)
		"orthographic":
			return sin(theta)
	var t2 := theta * theta
	return theta * (1.0 + t2 * (kb[0] + t2 * (kb[1] + t2 * (kb[2] + t2 * kb[3]))))

func _brown(x: float, y: float) -> Vector2:
	var r2 := x * x + y * y
	var radial := 1.0 + r2 * (brown[0] + r2 * (brown[1] + r2 * brown[4]))
	return Vector2(x * radial + 2.0 * brown[2] * x * y + brown[3] * (r2 + 2.0 * x * x),
		y * radial + brown[2] * (r2 + 2.0 * y * y) + 2.0 * brown[3] * x * y)

# Unit ray (optical frame) seen at pixel (u, v); Vector3.ZERO when no ray maps there.
func pixel_to_ray(u: float, v: float) -> Vector3:
	var yd := (v - cy) / fy
	var xd := (u - cx - skew * yd) / fx
	var ray: Vector3
	if projection == "perspective":
		var x := xd
		var y := yd
		if distortion == "brown_conrady":
			for i in ITERATIONS:
				var r2 := x * x + y * y
				var icdist := 1.0 / (1.0 + r2 * (brown[0] + r2 * (brown[1] + r2 * brown[4])))
				var dx := 2.0 * brown[2] * x * y + brown[3] * (r2 + 2.0 * x * x)
				var dy := brown[2] * (r2 + 2.0 * y * y) + 2.0 * brown[3] * x * y
				x = (xd - dx) * icdist
				y = (yd - dy) * icdist
			if (_brown(x, y) - Vector2(xd, yd)).length() > RESIDUAL_LIMIT:
				return Vector3.ZERO
		ray = Vector3(x, y, 1.0).normalized()
	else:
		var rho := Vector2(xd, yd).length()
		var theta := _theta_of_radius(rho)
		if theta < 0.0:
			return Vector3.ZERO
		ray = Vector3(sin(theta) * xd / rho, sin(theta) * yd / rho, cos(theta)) if rho > 0.0 else Vector3(0, 0, 1)
	if atan2(Vector2(ray.x, ray.y).length(), ray.z) > cutoff_angle:
		return Vector3.ZERO
	return ray

# Angle from the axis for normalized image radius rho; negative when none.
func _theta_of_radius(rho: float) -> float:
	match projection:
		"equidistant":
			return rho
		"equisolid_angle":
			return 2.0 * asin(rho / 2.0) if rho <= 2.0 else -1.0
		"stereographic":
			return 2.0 * atan(rho / 2.0)
		"orthographic":
			return asin(rho) if rho <= 1.0 else -1.0
	var theta := rho
	for i in ITERATIONS:
		var t2 := theta * theta
		var f := theta * (1.0 + t2 * (kb[0] + t2 * (kb[1] + t2 * (kb[2] + t2 * kb[3])))) - rho
		var df := 1.0 + t2 * (3.0 * kb[0] + t2 * (5.0 * kb[1] + t2 * (7.0 * kb[2] + t2 * 9.0 * kb[3])))
		if df <= 0.0:
			return -1.0
		theta -= f / df
	if theta < 0.0 or theta >= PI or absf(_image_radius(theta) - rho) > RESIDUAL_LIMIT:
		return -1.0
	return theta

# The ideal pinhole image covering every ray of the output image (lens.py source_camera).
func compute_source(grid_step := 8) -> bool:
	source_focal = maxf(fx, fy)
	var max_tx := 0.0
	var max_ty := 0.0
	var points: Array[Vector2i] = []
	for u in width:
		points.append(Vector2i(u, 0))
		points.append(Vector2i(u, height - 1))
	for v in height:
		points.append(Vector2i(0, v))
		points.append(Vector2i(width - 1, v))
	var us: Array = range(0, width, grid_step)
	us.append(width - 1)
	var vs: Array = range(0, height, grid_step)
	vs.append(height - 1)
	for u in us:
		for v in vs:
			points.append(Vector2i(u, v))
	for p in points:
		var ray := pixel_to_ray(p.x, p.y)
		if ray == Vector3.ZERO:
			continue
		var theta := atan2(Vector2(ray.x, ray.y).length(), ray.z)
		if theta > MAX_SOURCE_ANGLE_RAD:
			error = "the lens sees %.1f deg off axis; one pinhole view holds %.0f deg" % [rad_to_deg(theta), rad_to_deg(MAX_SOURCE_ANGLE_RAD)]
			return false
		max_tx = maxf(max_tx, absf(ray.x / ray.z))
		max_ty = maxf(max_ty, absf(ray.y / ray.z))
	# Same parity as the output: the two pixel grids stay aligned (lens.py).
	source_width = 2 * (ceili(source_focal * max_tx) + 2) + width % 2
	source_height = 2 * (ceili(source_focal * max_ty) + 2) + height % 2
	return true

func source_horizontal_fov() -> float:
	return 2.0 * atan(source_width / 2.0 / source_focal)

func set_shader_parameters(material: ShaderMaterial, source_texture: Texture2D) -> void:
	material.set_shader_parameter("source_image", source_texture)
	material.set_shader_parameter("output_size", Vector2(width, height))
	material.set_shader_parameter("intrinsics", Vector4(fx, fy, cx, cy))
	material.set_shader_parameter("skew", skew)
	material.set_shader_parameter("projection", PROJECTION_IDS[projection])
	material.set_shader_parameter("use_brown", distortion == "brown_conrady")
	material.set_shader_parameter("brown", Vector4(brown[0], brown[1], brown[2], brown[3]))
	material.set_shader_parameter("brown_k3", brown[4])
	material.set_shader_parameter("kb", Vector4(kb[0], kb[1], kb[2], kb[3]))
	material.set_shader_parameter("cutoff_angle", cutoff_angle)
	material.set_shader_parameter("source", Vector3(source_focal, (source_width - 1) / 2.0, (source_height - 1) / 2.0))
	material.set_shader_parameter("source_size", Vector2(source_width, source_height))
