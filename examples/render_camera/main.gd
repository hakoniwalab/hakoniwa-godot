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
#   --world-glb=<path>          draw this glTF world (loaded at run time) instead of the boxes
#   --camera-pose=x,y,z,yaw_deg use this camera pose (ROS world frame, m and deg) instead of the request's
#   --save-frame-dir=<dir>      save the 10th rendered frame of each size as PNG

const SimNodeScript = preload("res://addons/hakoniwa/scripts/hakoniwa_simulation_node.gd")
const CodecNodeScript = preload("res://addons/hakoniwa/scripts/hakoniwa_codec_node.gd")
const ASSET_NAME := "GodotRenderCamera"
const SERVICE_NAME := "HakoCamera/RenderCamera"
const PACKAGE := "hako_srv_msgs"

var _sim = null
var _codec = null
var _server: HakoniwaServiceServer = null
var _pending_response := PackedByteArray()
var _viewport: SubViewport
var _camera: Camera3D
var _rotor: MeshInstance3D
var _world_glb := ""
var _camera_pose_override := {}
var _save_frame_dir := ""

func _ready() -> void:
	# --headless uses the dummy renderer: nothing is drawn and get_image() returns null.
	if DisplayServer.get_name() == "headless":
		_quit("RenderCamera needs a GPU renderer; --headless has none (run with a window)")
		return
	RenderingServer.render_loop_enabled = false
	var service_json := ""
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
	if service_json.is_empty():
		_quit("--service-json=<path> is required")
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
	if _server.create(ASSET_NAME, SERVICE_NAME) < 0:
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
	var request: Dictionary = registry.decode(PACKAGE, "RenderCameraRequestPacket", _server.get_request())
	var body: Dictionary = request["body"]
	var size := _parse_size(String(body["camera_name"]))
	var seq := int(body["sim_time_usec"])

	var t1 := Time.get_ticks_usec()
	var pixels := PackedByteArray()
	var image: Image = null
	if size.x > 0 and size.y > 0:
		if _viewport.size != size:
			_viewport.size = size
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

	var response: Dictionary = registry.decode(PACKAGE, "RenderCameraResponsePacket", _server.get_response_template())
	response["body"]["result_code"] = 0
	response["body"]["sim_time_usec"] = seq
	var image_msg: Dictionary = response["body"]["image"]
	image_msg["height"] = size.y
	image_msg["width"] = size.x
	image_msg["encoding"] = "rgb8"
	image_msg["is_bigendian"] = 0
	image_msg["step"] = size.x * 3
	image_msg["data"] = pixels
	var packet: PackedByteArray = registry.encode(PACKAGE, "RenderCameraResponsePacket", response)
	var t4 := Time.get_ticks_usec()
	_put_response(packet)
	var t5 := Time.get_ticks_usec()
	print("FRAME seq=%d size=%dx%d decode_us=%d draw_us=%d readback_us=%d encode_us=%d put_us=%d" % [
		seq, size.x, size.y, t1 - t0, t2 - t1, t3 - t2, t4 - t3, t5 - t4])
	if seq == 10 and image != null and not _save_frame_dir.is_empty():
		image.save_png(_save_frame_dir.path_join("frame_%dx%d.png" % [size.x, size.y]))

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
	var world := Node3D.new()
	_viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
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
	_camera.fov = 70.0
	_camera.near = 0.1
	_camera.far = 1000.0
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
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	world.add_child(env)
	_rotor = MeshInstance3D.new()
	world.add_child(_rotor)
	_add_camera(world)
	print("WORLD loaded %s meshes=%d load_ms=%d" % [_world_glb, state.get_meshes().size(), (Time.get_ticks_usec() - t0) / 1000])
	return true

# ROS ENU is right-handed (x forward, y left, z up); Godot is y up and the camera
# looks down its local -z. Position (x, y, z) maps to Godot (-y, z, -x); the
# orientation is applied in ROS space and converted with the same basis change.
func _apply_ros_enu_pose(pose: Dictionary) -> void:
	var p: Dictionary = pose.get("position", {})
	var q: Dictionary = pose.get("orientation", {})
	var qw := float(q.get("w", 1.0))
	var ros_rotation := Quaternion(float(q.get("x", 0.0)), float(q.get("y", 0.0)), float(q.get("z", 0.0)), qw if qw != 0.0 else 1.0)
	var conversion := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))
	_camera.transform = Transform3D(
		conversion * Basis(ros_rotation) * conversion.inverse(),
		Vector3(-float(p.get("y", 0.0)), float(p.get("z", 0.0)), -float(p.get("x", 0.0))))

func _quit(message: String) -> void:
	push_error(message)
	print("SERVER init failed: %s" % message)
	get_tree().quit(1)
