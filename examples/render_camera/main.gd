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

func _ready() -> void:
	RenderingServer.render_loop_enabled = false
	var service_json := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--service-json="):
			service_json = arg.trim_prefix("--service-json=")
	if service_json.is_empty():
		_quit("--service-json=<path> is required")
		return
	if load("res://addons/hakoniwa/hakoniwa.gdextension") == null:
		_quit("hakoniwa extension could not be loaded")
		return
	_build_world()

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
	if size.x > 0 and size.y > 0:
		if _viewport.size != size:
			_viewport.size = size
		_rotor.rotation.y = fmod(float(simtime_usec) * 0.000001, TAU)
		_apply_ros_enu_pose(body["camera_pose"])
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		RenderingServer.force_draw(false)
	var t2 := Time.get_ticks_usec()
	if size.x > 0 and size.y > 0:
		var image := _viewport.get_texture().get_image()
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

# A heavy-ish background: about 1,500 boxes, a shadowed sun and a rotating bar.
func _build_world() -> void:
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
	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.near = 0.1
	_camera.far = 500.0
	world.add_child(_camera)

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
