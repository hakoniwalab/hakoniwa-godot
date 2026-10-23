extends Node

# Service/Add server in Godot, as a registered polling asset in the Hakoniwa time
# synchronization. One physics tick (1 ms) is one Hakoniwa step; the service is
# polled in that step, only while Running (HakoniwaSimNode emits simulation_step
# only then). The server is created on the Start event, before the start feedback,
# so a client cannot send a request before the server exists.
# Run headless with --fixed-fps 1000: one frame = one physics tick, no real-time pacing.

const SimNodeScript = preload("res://addons/hakoniwa/scripts/hakoniwa_simulation_node.gd")
const CodecNodeScript = preload("res://addons/hakoniwa/scripts/hakoniwa_codec_node.gd")
const ASSET_NAME := "GodotAddServer"
const SERVICE_NAME := "Service/Add"
const PACKAGE := "hako_srv_msgs"

var _sim = null
var _codec = null
var _server: HakoniwaServiceServer = null
var _pending_response := PackedByteArray()

func _ready() -> void:
	if load("res://addons/hakoniwa/hakoniwa.gdextension") == null:
		_quit("hakoniwa extension could not be loaded")
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
	if _server.initialize_service(ProjectSettings.globalize_path("res://config/service.json")) != 0:
		_quit(_server.get_last_error_text())
		return
	print("SERVER registered; service declared in Stopped delta_usec=%d" % _sim.get_configured_delta_time_usec())

func on_simulation_start() -> void:
	if _server.create(ASSET_NAME, SERVICE_NAME) < 0:
		push_error(_server.get_last_error_text())
		return
	print("SERVER event Start")

func on_simulation_stop() -> void:
	# A response of this run must not be written in the next one.
	_pending_response = PackedByteArray()
	print("SERVER event Stop")

func on_simulation_reset() -> void:
	print("SERVER event Reset")

func _on_simulation_step(simtime_usec: int, _world_time_usec: int) -> void:
	# Simulation time against wall time, for the RTF.
	if simtime_usec % 1000000 == 0:
		print("RTF_SAMPLE sim_usec=%d wall_usec=%d" % [simtime_usec, Time.get_ticks_usec()])
	if not _pending_response.is_empty():
		_put_response(_pending_response)
		return
	if _server.poll() != HakoniwaServiceServer.EVENT_REQUEST_IN:
		return
	var registry: Node = _codec.get_registry()
	var request: Dictionary = registry.decode(PACKAGE, "AddTwoIntsRequestPacket", _server.get_request())
	var response: Dictionary = registry.decode(PACKAGE, "AddTwoIntsResponsePacket", _server.get_response_template())
	var a := int(request["body"]["a"])
	var b := int(request["body"]["b"])
	response["body"]["sum"] = a + b
	print("SERVER request a=%d b=%d sum=%d server_time_usec=%d" % [a, b, a + b, simtime_usec])
	_put_response(registry.encode(PACKAGE, "AddTwoIntsResponsePacket", response))

# put_response returns 1 while the response channel is busy: keep the packet and
# try again on the next step.
func _put_response(packet: PackedByteArray) -> void:
	var rc := _server.put_response(packet)
	if rc == 1:
		_pending_response = packet
		return
	_pending_response = PackedByteArray()
	if rc != 0:
		push_error(_server.get_last_error_text())

func _quit(message: String) -> void:
	push_error(message)
	print("SERVER init failed: %s" % message)
	get_tree().quit(1)
