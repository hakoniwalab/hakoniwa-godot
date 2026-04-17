extends Node

const STEP_TARGET := 3
const START_VALUE := 101
const REPLY_VALUE := 1001
const WATCHDOG_SEC := 10.0

var _sim = null
var _endpoint = null
var _subscription_id := -1
var _step_count := 0
var _recv_count := 0
var _completed := false
var _elapsed_sec := 0.0

func _ready() -> void:
	print("HAKO_PYTHON_PDU_MINIMAL_GODOT_BOOT")

	var extension: Resource = load("res://addons/hakoniwa/hakoniwa.gdextension")
	if extension == null:
		_fail("HAKO_PYTHON_PDU_MINIMAL_GODOT_EXTENSION_LOAD_FAILED")
		return

	var sim_script = load("res://addons/hakoniwa/scripts/hakoniwa_simulation_node.gd")
	if sim_script == null:
		_fail("HAKO_PYTHON_PDU_MINIMAL_GODOT_SIM_SCRIPT_LOAD_FAILED")
		return

	_sim = sim_script.new()
	add_child(_sim)
	_sim.asset_name = "godot_python_pdu_minimal"
	_sim.delta_time_usec = 20000
	_sim.use_internal_shm_endpoint = true
	_sim.shm_endpoint_config_path = "res://config/endpoint_shm_with_pdu.json"
	_sim.internal_endpoint_codec_plugins = PackedStringArray([
		"res://addons/hakoniwa/codecs/std_msgs_codec"
	])
	_sim.simulation_started.connect(_on_simulation_started)
	_sim.simulation_stopped.connect(_on_simulation_stopped)
	_sim.simulation_reset.connect(_on_simulation_reset)
	_sim.simulation_step.connect(_on_simulation_step)

	var initialize_result: int = _sim.initialize()
	if initialize_result != 0:
		_fail("HAKO_PYTHON_PDU_MINIMAL_GODOT_INITIALIZE_FAILED", _sim.get_last_error_text())
		return

	_endpoint = _sim.get_endpoint()
	if _endpoint == null:
		_fail("HAKO_PYTHON_PDU_MINIMAL_GODOT_ENDPOINT_ACCESS_FAILED", _sim.get_last_error_text())
		return

	_subscription_id = _endpoint.create_subscription_message(
		"Robot",
		"python_to_godot",
		"std_msgs",
		"UInt64",
		Callable(self, "_on_python_message"))
	if _subscription_id < 0:
		_fail("HAKO_PYTHON_PDU_MINIMAL_GODOT_SUBSCRIBE_FAILED", _endpoint.get_last_error_text())
		return

	print("HAKO_PYTHON_PDU_MINIMAL_GODOT_READY")

	var start_result: int = _sim.request_start()
	if start_result != 0:
		_fail("HAKO_PYTHON_PDU_MINIMAL_GODOT_REQUEST_START_FAILED", _sim.get_last_error_text())

func _process(delta: float) -> void:
	if _completed:
		return
	_elapsed_sec += delta
	if _elapsed_sec >= WATCHDOG_SEC:
		_fail("HAKO_PYTHON_PDU_MINIMAL_GODOT_TIMEOUT")

func _on_simulation_started() -> void:
	print("HAKO_PYTHON_PDU_MINIMAL_GODOT_START_FEEDBACK_OK")

func _on_simulation_stopped() -> void:
	print("HAKO_PYTHON_PDU_MINIMAL_GODOT_STOP_FEEDBACK_OK")

func _on_simulation_reset() -> void:
	print("HAKO_PYTHON_PDU_MINIMAL_GODOT_RESET_FEEDBACK_OK")

func _on_simulation_step(simtime_usec: int, world_time_usec: int) -> void:
	if _completed:
		return
	if _step_count >= STEP_TARGET:
		return

	var next_count := _step_count + 1
	var value := START_VALUE + _step_count
	var send_result: int = _endpoint.send_message(
		"Robot",
		"godot_to_python",
		"std_msgs",
		"UInt64",
		{"data": value})
	if send_result != 0:
		_fail("HAKO_PYTHON_PDU_MINIMAL_GODOT_SEND_FAILED", _endpoint.get_last_error_text())
		return

	_step_count = next_count
	print("HAKO_PYTHON_PDU_MINIMAL_GODOT_SEND:%d:simtime=%d:world=%d:value=%d" % [
		_step_count,
		simtime_usec,
		world_time_usec,
		value
	])

func _on_python_message(message: Dictionary) -> void:
	if _completed:
		return
	_recv_count += 1
	print("HAKO_PYTHON_PDU_MINIMAL_GODOT_RECV:%d:value=%d" % [
		_recv_count,
		int(message.get("data", -1))
	])
	if _recv_count >= STEP_TARGET and _step_count >= STEP_TARGET:
		_completed = true
		print("HAKO_PYTHON_PDU_MINIMAL_GODOT_OK")
		get_tree().quit(0)

func _fail(marker: String, detail: String = "") -> void:
	print(marker)
	if not detail.is_empty():
		print(detail)
	get_tree().quit(2)
