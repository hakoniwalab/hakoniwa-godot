extends Node

# HakoCamera/RenderCamera server in Godot: a registered polling asset with a 1 ms
# physics tick. Godot does not render on its own (render loop off); a request is
# rendered inside the simulation step that receives it (RenderingServer.force_draw),
# read back and answered before the next step, so the simulation time does not move
# while rendering.
# Run with a window (rendering needs the GPU), not --headless:
#   Godot --fixed-fps 1000 --path examples/render_camera -- --service-json=<service.json>
# camera_name of the request is "<width>x<height>". The first byte of the image is
# overwritten with the request number (sim_time_usec & 0xff) so the benchmark client
# can match the response to its request.
# Options (after --):
#   --service=frame            serve HakoCamera/RenderCameraFrame (legacy service otherwise)
#   --profiles=<dir>           camera profile JSON directory (required for frame service)
#   --world-glb=<path>          draw this glTF world (loaded at run time) instead of the boxes
#   --camera-pose=x,y,z,yaw_deg use this camera pose (ROS world frame, m and deg) instead of the request's
#   --save-frame-dir=<dir>      save the 10th rendered frame of each size as PNG
#   --test-chart=x,y,z,yaw_deg  place a reflectance test chart (ROS world frame, m and deg)
#   --test-board=x,y,z,yaw,pitch,roll,cols,rows,square_m  place a calibration checkerboard
#   --sun-time=, --sun-lux=, --sun-kelvin=, --sky-intensity=, --latitude=, --longitude=,
#   --auto-exposure-speed=      daylight in physical units, auto exposure speed (lighting.gd)
#   --light-step=sim_sec,factor scale all daylight by factor from this simulation time
#   --probe=x,y                 print the mean 8-bit RGB of 9 x 9 pixels at (x, y) every frame
#                               daylight in physical units (lighting.gd)

const SimNodeScript = preload("res://addons/hakoniwa/scripts/hakoniwa_simulation_node.gd")
const CodecNodeScript = preload("res://addons/hakoniwa/scripts/hakoniwa_codec_node.gd")
const Lighting = preload("res://lighting.gd")
const Lens = preload("res://lens.gd")
const ASSET_NAME := "GodotRenderCamera"
const PACKAGE := "hako_srv_msgs"
const LEGACY_SERVICE_NAME := "HakoCamera/RenderCamera"
const FRAME_SERVICE_NAME := "HakoCamera/RenderCameraFrame"

var _sim = null
var _codec = null
var _server: HakoniwaServiceServer = null
var _pending_response := PackedByteArray()
var _viewport: SubViewport
# A lens that is not an ideal centred pinhole (spec.lens, memo 025): _viewport draws a
# wider ideal pinhole image and _warp_viewport maps it to the lens's image.
var _warp_viewport: SubViewport
var _warp_material: ShaderMaterial
# Wide lenses: one viewport and camera per cube face, by face name (lens.gd CUBE_FACES).
# They share the world (SubViewports use the root's World3D) and the camera attributes.
var _face_views := {}
var _camera: Camera3D
var _rotor: MeshInstance3D
var _world_glb := ""
var _camera_pose_override := {}
var _save_frame_dir := ""
var _service_name := LEGACY_SERVICE_NAME
var _request_packet := "RenderCameraRequestPacket"
var _response_packet := "RenderCameraResponsePacket"
var _frame_service := false
var _profiles := {}
var _lighting = Lighting.new()
var _camera_attributes: CameraAttributesPhysical
var _test_chart := PackedFloat64Array()
var _test_board := PackedFloat64Array()
var _light_step := PackedFloat64Array()
var _light_step_done := false
var _probe := PackedInt32Array()
# Simulation time of each camera's previous frame. force_draw's frame step is the
# time effects that adapt over time (auto exposure) see; 0 would freeze them.
var _last_frame_usec := {}

func _ready() -> void:
	# --headless uses the dummy renderer: nothing is drawn and get_image() returns null.
	if DisplayServer.get_name() == "headless":
		_quit("RenderCamera needs a GPU renderer; --headless has none (run with a window)")
		return
	RenderingServer.render_loop_enabled = false
	var service_json := ""
	var profiles_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--service-json="):
			service_json = arg.trim_prefix("--service-json=")
		elif arg.begins_with("--world-glb="):
			_world_glb = arg.trim_prefix("--world-glb=")
		elif arg.begins_with("--camera-pose="):
			var v := arg.trim_prefix("--camera-pose=").split_floats(",")
			if v.size() == 4:
				var yaw := deg_to_rad(v[3])
				_camera_pose_override = {
					"position": {"x": v[0], "y": v[1], "z": v[2]},
					"orientation": {"x": 0.0, "y": 0.0, "z": sin(yaw * 0.5), "w": cos(yaw * 0.5)}}
		elif arg.begins_with("--save-frame-dir="):
			_save_frame_dir = arg.trim_prefix("--save-frame-dir=")
		elif arg == "--service=frame":
			_frame_service = true
			_service_name = FRAME_SERVICE_NAME
			_request_packet = "RenderCameraFrameRequestPacket"
			_response_packet = "RenderCameraFrameResponsePacket"
		elif arg.begins_with("--profiles="):
			profiles_dir = arg.trim_prefix("--profiles=")
		elif arg.begins_with("--light-step="):
			_light_step = arg.trim_prefix("--light-step=").split_floats(",")
		elif arg.begins_with("--probe="):
			var xy := arg.trim_prefix("--probe=").split_floats(",")
			_probe = PackedInt32Array([int(xy[0]), int(xy[1])])
		elif arg.begins_with("--test-board="):
			_test_board = arg.trim_prefix("--test-board=").split_floats(",")
		elif arg.begins_with("--test-chart="):
			_test_chart = arg.trim_prefix("--test-chart=").split_floats(",")
		elif _lighting.parse_option(arg):
			pass
	if service_json.is_empty():
		_quit("--service-json=<path> is required")
		return
	if _frame_service:
		if profiles_dir.is_empty():
			_quit("--profiles=<dir> is required with --service=frame")
			return
		_load_profiles(profiles_dir)
		if _profiles.is_empty():
			_quit("no valid camera profiles found in: %s" % profiles_dir)
			return
	if load("res://addons/hakoniwa/hakoniwa.gdextension") == null:
		_quit("hakoniwa extension could not be loaded")
		return
	if not _build_world():
		return

	_codec = CodecNodeScript.new()
	_codec.codec_manifest_path = "res://codec_manifest.json"
	_codec.load_on_ready = false
	add_child(_codec)
	if not _codec.initialize():
		_quit(_codec.last_error)
		return

	_sim = SimNodeScript.new()
	_sim.asset_name = ASSET_NAME
	_sim.enable_physics_time_sync = true
	_sim.auto_sync_delta_time_with_physics = true
	add_child(_sim)
	_sim.set_callbacks(self)
	_sim.simulation_step.connect(_on_simulation_step)
	if _sim.initialize() != 0:
		_quit(_sim.get_last_error_text())
		return

	# Declared while Stopped, before the first start.
	_server = HakoniwaServiceServer.new()
	add_child(_server)
	if _server.initialize_service(service_json) != 0:
		_quit(_server.get_last_error_text())
		return
	print("SERVER registered; service declared in Stopped delta_usec=%d renderer=%s" % [
		_sim.get_configured_delta_time_usec(), RenderingServer.get_current_rendering_method()])

func on_simulation_start() -> void:
	if _server.create(ASSET_NAME, _service_name) < 0:
		push_error(_server.get_last_error_text())
		return
	print("SERVER event Start")

func on_simulation_stop() -> void:
	_pending_response = PackedByteArray()
	print("SERVER event Stop")

func on_simulation_reset() -> void:
	print("SERVER event Reset")

func _on_simulation_step(simtime_usec: int, _world_time_usec: int) -> void:
	if simtime_usec % 1000000 == 0:
		print("RTF_SAMPLE sim_usec=%d wall_usec=%d" % [simtime_usec, Time.get_ticks_usec()])
	if not _pending_response.is_empty():
		_put_response(_pending_response)
		return
	if _server.poll() != HakoniwaServiceServer.EVENT_REQUEST_IN:
		return
	var t0 := Time.get_ticks_usec()
	var registry: Node = _codec.get_registry()
	var request: Dictionary = registry.decode(PACKAGE, _request_packet, _server.get_request())
	var body: Dictionary = request["body"]
	if _frame_service:
		_handle_frame_request(registry, body)
		return
	var size := _parse_size(String(body["camera_name"]))
	var seq := int(body["sim_time_usec"])

	var t1 := Time.get_ticks_usec()
	var pixels := PackedByteArray()
	var image: Image = null
	if size.x > 0 and size.y > 0:
		_resize_viewport(size)
		_rotor.rotation.y = fmod(float(simtime_usec) * 0.000001, TAU)
		_apply_ros_enu_pose(_camera_pose_override if not _camera_pose_override.is_empty() else body["camera_pose"])
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		RenderingServer.force_draw(false)
	var t2 := Time.get_ticks_usec()
	if size.x > 0 and size.y > 0:
		image = _viewport.get_texture().get_image()
		image.convert(Image.FORMAT_RGB8)
		pixels = image.get_data()
		pixels[0] = seq & 0xff
	var t3 := Time.get_ticks_usec()

	var response: Dictionary = registry.decode(PACKAGE, _response_packet, _server.get_response_template())
	response["body"]["result_code"] = 0
	response["body"]["sim_time_usec"] = seq
	var image_msg: Dictionary = response["body"]["image"]
	image_msg["height"] = size.y
	image_msg["width"] = size.x
	image_msg["encoding"] = "rgb8"
	image_msg["is_bigendian"] = 0
	image_msg["step"] = size.x * 3
	image_msg["data"] = pixels
	var packet: PackedByteArray = registry.encode(PACKAGE, _response_packet, response)
	var t4 := Time.get_ticks_usec()
	_put_response(packet)
	var t5 := Time.get_ticks_usec()
	print("FRAME seq=%d size=%dx%d decode_us=%d draw_us=%d readback_us=%d encode_us=%d put_us=%d" % [
		seq, size.x, size.y, t1 - t0, t2 - t1, t3 - t2, t4 - t3, t5 - t4])
	if seq == 10 and image != null and not _save_frame_dir.is_empty():
		image.save_png(_save_frame_dir.path_join("frame_%dx%d.png" % [size.x, size.y]))

func _handle_frame_request(registry: Node, body: Dictionary) -> void:
	var camera_name := String(body["camera_name"])
	var sim_time_usec := int(body["sim_time_usec"])
	var outputs := int(body["outputs"])
	var response: Dictionary = registry.decode(PACKAGE, _response_packet, _server.get_response_template())
	response["body"]["sim_time_usec"] = sim_time_usec
	var profile: Dictionary = _profiles.get(camera_name, {})
	if profile.is_empty():
		response["body"]["result_code"] = 1
		var missing_packet: PackedByteArray = registry.encode(PACKAGE, _response_packet, response)
		_put_response(missing_packet)
		print("TIMING sim_time_usec=%d camera=%s draw_ms=0.000 readback_ms=0.000 convert_ms=0.000 encode_ms=0.000 put_response_ms=0.000 result_code=1" % [sim_time_usec, camera_name])
		return

	response["body"]["result_code"] = 0
	var draw_start := Time.get_ticks_usec()
	var image: Image = null
	if outputs & 1:
		var size := Vector2i(profile["width"], profile["height"])
		var lens = profile["lens"]
		var warp: bool = not lens.is_ideal()
		var fov: float = profile["horizontal_fov"]
		if warp:
			fov = lens.cube_fov() if lens.cube else lens.source_horizontal_fov()
		if not lens.cube:
			_resize_viewport(Vector2i(lens.source_width, lens.source_height) if warp else size)
		_camera.keep_aspect = Camera3D.KEEP_WIDTH
		Lighting.apply_lens(_camera_attributes, fov, profile["near"], profile["far"])
		_lighting.apply_exposure(_camera_attributes, profile["exposure"])
		_lighting.apply_color(profile["photometric"])
		_apply_ros_enu_pose(body["camera_pose"])
		# Lens effects are defined on the output image; they need the lens and the image
		# drawn for it (the output itself, a wider pinhole or cube faces).
		var drawn_focal: float = lens.fx
		if warp:
			drawn_focal = lens.cube_focal if lens.cube else lens.source_focal
		_lighting.lens_effects.set_geometry(lens, drawn_focal, _camera.global_transform.basis)
		_lighting.set_pixel_angle(drawn_focal)
		if warp:
			if _warp_viewport.size != size:
				_warp_viewport.size = size
			var textures := {"source": _viewport.get_texture()}
			if lens.cube:
				textures = _draw_cube_faces(lens)
			lens.set_shader_parameters(_warp_material, textures)
			_warp_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		if _light_step.size() == 2 and not _light_step_done and sim_time_usec >= int(_light_step[0] * 1000000.0):
			_lighting.scale_light(_light_step[1])
			_light_step_done = true
		if not (warp and lens.cube):
			_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		var frame_step := _frame_step_sec(camera_name, sim_time_usec)
		_lighting.auto_exposure.begin_frame(camera_name)
		RenderingServer.force_draw(false, frame_step)
	var readback_start := Time.get_ticks_usec()
	if outputs & 1:
		var target := _warp_viewport if not profile["lens"].is_ideal() else _viewport
		image = target.get_texture().get_image()
		# The frame is drawn: meter it for the next frames of this camera.
		_lighting.auto_exposure.end_frame(_last_frame_step)
	var convert_start := Time.get_ticks_usec()
	if image != null:
		image.convert(Image.FORMAT_RGB8)
		if _probe.size() == 2:
			_print_probe(image, sim_time_usec)
		var rgb: Dictionary = response["body"]["rgb"]
		_set_image_header(rgb, sim_time_usec, camera_name)
		rgb["height"] = profile["height"]
		rgb["width"] = profile["width"]
		rgb["encoding"] = "rgb8"
		rgb["is_bigendian"] = 0
		rgb["step"] = int(profile["width"]) * 3
		rgb["data"] = image.get_data()
	var encode_start := Time.get_ticks_usec()
	var packet: PackedByteArray = registry.encode(PACKAGE, _response_packet, response)
	var put_start := Time.get_ticks_usec()
	_put_response(packet)
	var done := Time.get_ticks_usec()
	print("TIMING sim_time_usec=%d camera=%s draw_ms=%.3f readback_ms=%.3f convert_ms=%.3f encode_ms=%.3f put_response_ms=%.3f result_code=0" % [
		sim_time_usec, camera_name, (readback_start - draw_start) / 1000.0,
		(convert_start - readback_start) / 1000.0, (encode_start - convert_start) / 1000.0,
		(put_start - encode_start) / 1000.0, (done - put_start) / 1000.0])

func _set_image_header(image_msg: Dictionary, sim_time_usec: int, frame_id: String) -> void:
	image_msg["header"]["stamp"]["sec"] = int(sim_time_usec / 1000000)
	image_msg["header"]["stamp"]["nanosec"] = (sim_time_usec % 1000000) * 1000
	image_msg["header"]["frame_id"] = frame_id

func _load_profiles(directory: String) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		_quit("could not open profiles directory: %s" % directory)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.get_extension() == "json":
			_load_profile(directory.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	print("PROFILES loaded=%d directory=%s" % [_profiles.size(), directory])

func _load_profile(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_profile_error(path, "/", "cannot open file")
		return
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		_profile_error(path, "/", "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return
	var root = json.data
	if typeof(root) != TYPE_DICTIONARY:
		_profile_error(path, "/", "must be an object")
		return
	var fields := [
		["/spec/frame_id", TYPE_STRING], ["/spec/image/width", TYPE_INT],
		["/spec/image/height", TYPE_INT], ["/spec/image/format", TYPE_STRING],
		["/spec/horizontal_fov", TYPE_FLOAT], ["/spec/clip/near", TYPE_FLOAT],
		["/spec/clip/far", TYPE_FLOAT]]
	var values := []
	for field in fields:
		var result := _profile_value(root, field[0])
		if not result[0]:
			_profile_error(path, field[0], "is required")
			return
		var value = result[1]
		var actual := typeof(value)
		var numeric: bool = field[1] == TYPE_FLOAT and (actual == TYPE_FLOAT or actual == TYPE_INT)
		# Godot's JSON parser returns every number as a float: 1280 comes back as 1280.0.
		if field[1] == TYPE_INT and actual == TYPE_FLOAT and value == floor(value):
			value = int(value)
			actual = TYPE_INT
		if actual != field[1] and not numeric:
			_profile_error(path, field[0], "has wrong type")
			return
		values.append(value)
	if values[0].is_empty() or values[1] <= 0 or values[2] <= 0 or values[4] <= 0.0 or values[5] <= 0.0 or values[6] <= values[5]:
		_profile_error(path, "/spec", "contains an invalid value")
		return
	var photometric = _profile_value(root, "/spec/photometric")[1]
	if photometric != null and typeof(photometric) != TYPE_DICTIONARY:
		_profile_error(path, "/spec/photometric", "must be an object")
		return
	if photometric == null:
		photometric = {}
	var exposure = photometric.get("exposure", {})
	if typeof(exposure) != TYPE_DICTIONARY:
		_profile_error(path, "/spec/photometric/exposure", "must be an object")
		return
	var lens = Lens.new()
	if not lens.load_spec(root["spec"]):
		_profile_error(path, "/spec/lens", lens.error)
		return
	if not lens.is_ideal() and not lens.compute_views():
		_profile_error(path, "/spec/lens", lens.error)
		return
	_profiles[values[0]] = {"width": values[1], "height": values[2], "format": values[3],
		"horizontal_fov": float(values[4]), "near": float(values[5]), "far": float(values[6]),
		"exposure": exposure, "photometric": photometric, "lens": lens}

# Point the face cameras along the cube faces of the main camera's pose and mark their
# viewports for this draw. Returns the face textures by name.
func _draw_cube_faces(lens) -> Dictionary:
	var textures := {}
	for name in lens.cube_face_names:
		var view: Dictionary = _face_view(name)
		var viewport: SubViewport = view["viewport"]
		var camera: Camera3D = view["camera"]
		var crop: Rect2i = lens.cube_crops[name]
		if viewport.size != crop.size:
			viewport.size = crop.size
		_set_crop_frustum(camera, crop, lens.cube_focal, (lens.cube_size - 1) / 2.0)
		camera.transform = _camera.transform * Transform3D(Lens.face_basis(name), Vector3.ZERO)
		camera.force_update_transform()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		textures[name] = viewport.get_texture()
	return textures

# Draw only the crop of a face: an off-axis frustum whose near-plane rectangle is the
# crop's pixel edges (pixel centres at integers, so a pixel spans +-0.5) seen through
# a pinhole of the face's focal length and centre. Godot's image y is up.
func _set_crop_frustum(camera: Camera3D, crop: Rect2i, focal: float, centre: float) -> void:
	var near := _camera_attributes.frustum_near
	var middle := Vector2(crop.position) + Vector2(crop.size) / 2.0 - Vector2(0.5, 0.5)
	camera.projection = Camera3D.PROJECTION_FRUSTUM
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = near * crop.size.x / focal
	camera.frustum_offset = Vector2(near * (middle.x - centre) / focal, -near * (middle.y - centre) / focal)
	camera.near = near
	camera.far = _camera_attributes.frustum_far

func _face_view(name: String) -> Dictionary:
	if _face_views.has(name):
		return _face_views[name]
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.use_taa = false
	var camera := Camera3D.new()
	camera.attributes = _camera_attributes
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	_lighting.attach_to(camera)
	viewport.add_child(camera)
	add_child(viewport)
	# Faces draw before the warp viewport that reads them.
	move_child(viewport, _warp_viewport.get_index())
	camera.current = true
	_face_views[name] = {"viewport": viewport, "camera": camera}
	return _face_views[name]

func _print_probe(image: Image, sim_time_usec: int) -> void:
	var sum := Vector3.ZERO
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var c := image.get_pixel(_probe[0] + dx, _probe[1] + dy)
			sum += Vector3(c.r8, c.g8, c.b8)
	sum /= 81.0
	print("PROBE sim_time_usec=%d r=%.1f g=%.1f b=%.1f" % [sim_time_usec, sum.x, sum.y, sum.z])

var _last_frame_step := 0.0

func _frame_step_sec(camera_name: String, sim_time_usec: int) -> float:
	var last: int = _last_frame_usec.get(camera_name, sim_time_usec)
	_last_frame_usec[camera_name] = sim_time_usec
	_last_frame_step = maxf(0.0, (sim_time_usec - last) / 1000000.0)
	return _last_frame_step

func _profile_value(root: Dictionary, pointer: String) -> Array:
	var value = root
	for part in pointer.trim_prefix("/").split("/"):
		if typeof(value) != TYPE_DICTIONARY or not value.has(part):
			return [false, null]
		value = value[part]
	return [true, value]

func _profile_error(path: String, field: String, message: String) -> void:
	push_warning("PROFILE file=%s field=%s ignored: %s" % [path, field, message])

func _put_response(packet: PackedByteArray) -> void:
	var rc := _server.put_response(packet)
	if rc == 1:
		_pending_response = packet
		return
	_pending_response = PackedByteArray()
	if rc != 0:
		push_error(_server.get_last_error_text())

func _parse_size(camera_name: String) -> Vector2i:
	var parts := camera_name.split("x")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))

# The world: a glTF file (--world-glb) or about 1,500 boxes; a shadowed sun and a rotating bar.
func _build_world() -> bool:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(640, 480)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.use_taa = false
	add_child(_viewport)
	# After _viewport in the tree, so it draws after the source it reads.
	_warp_viewport = SubViewport.new()
	_warp_viewport.size = Vector2i(640, 480)
	_warp_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_warp_viewport.disable_3d = true
	var warp_rect := ColorRect.new()
	warp_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_warp_material = ShaderMaterial.new()
	_warp_material.shader = preload("res://lens_warp.gdshader")
	warp_rect.material = _warp_material
	_warp_viewport.add_child(warp_rect)
	add_child(_warp_viewport)
	var world := Node3D.new()
	_viewport.add_child(world)
	_lighting.add_to(world)
	if _test_chart.size() >= 4:
		Lighting.add_test_chart(world, _test_chart)
	if _test_board.size() == 9:
		Lighting.add_test_board(world, _test_board)
	if not _world_glb.is_empty():
		return _load_world_glb(world)
	var box := BoxMesh.new()
	box.size = Vector3(2.2, 1.0, 2.2)
	for x in range(-22, 23):
		for z in range(-22, 23):
			if x % 4 == 0 or z % 4 == 0:
				continue
			var building := MeshInstance3D.new()
			building.mesh = box
			var height := 2.0 + float(posmod(x * 17 + z * 31, 18))
			building.scale = Vector3(0.75, height, 0.75)
			building.position = Vector3(x * 3.0, height * 0.5, z * 3.0)
			world.add_child(building)
	_rotor = MeshInstance3D.new()
	var rotor_mesh := BoxMesh.new()
	rotor_mesh.size = Vector3(12, 0.3, 1)
	_rotor.mesh = rotor_mesh
	_rotor.position = Vector3(0, 18, 0)
	world.add_child(_rotor)
	_add_camera(world)
	return true

func _add_camera(world: Node3D) -> void:
	_camera = Camera3D.new()
	# Physical exposure; the attributes also set the field of view and the clip.
	# The legacy service keeps its 70 degree vertical field of view.
	_camera_attributes = Lighting.make_camera_attributes()
	_camera.attributes = _camera_attributes
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	Lighting.apply_lens(_camera_attributes, deg_to_rad(70.0), 0.1, 1000.0)
	_lighting.attach_to(_camera)
	world.add_child(_camera)

# The city GLB is "X=East, Y=Up, Z=-North" (a local ENU frame), which is Godot's frame
# as it is: it is placed without a transform, like the three.js viewer does.
func _load_world_glb(world: Node3D) -> bool:
	var t0 := Time.get_ticks_usec()
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_file(_world_glb, state)
	if err != OK:
		_quit("could not load %s (error %d)" % [_world_glb, err])
		return false
	var scene := gltf.generate_scene(state)
	world.add_child(scene)
	_rotor = MeshInstance3D.new()
	world.add_child(_rotor)
	_add_camera(world)
	print("WORLD loaded %s meshes=%d load_ms=%d" % [_world_glb, state.get_meshes().size(), (Time.get_ticks_usec() - t0) / 1000])
	return true

# ROS ENU is right-handed (x forward, y left, z up); Godot is y up and the camera
# looks down its local -z. Position (x, y, z) maps to Godot (-y, z, -x); the
# orientation is applied in ROS space and converted with the same basis change.
func _resize_viewport(size: Vector2i) -> void:
	if _viewport.size != size:
		_viewport.size = size

func _apply_ros_enu_pose(pose: Dictionary) -> void:
	var p: Dictionary = pose.get("position", {})
	var q: Dictionary = pose.get("orientation", {})
	var qw := float(q.get("w", 1.0))
	var ros_rotation := Quaternion(float(q.get("x", 0.0)), float(q.get("y", 0.0)), float(q.get("z", 0.0)), qw if qw != 0.0 else 1.0)
	var conversion := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))
	_camera.transform = Transform3D(
		conversion * Basis(ros_rotation) * conversion.inverse(),
		Vector3(-float(p.get("y", 0.0)), float(p.get("z", 0.0)), -float(p.get("x", 0.0))))
	# A new transform reaches the renderer only at the end of the frame; force_draw
	# inside the same step would draw from the previous pose (one request late).
	_camera.force_update_transform()

func _quit(message: String) -> void:
	push_error(message)
	print("SERVER init failed: %s" % message)
	get_tree().quit(1)
