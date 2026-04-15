extends Node

const STEP_TARGET := 5

var _sim = null
var _motor_endpoint = null
var _pos_endpoint = null
var _callbacks = null
var _step_count := 0
var _completed := false
var _latest_motor := {}
var _motor_subscription_id := -1

func _ready() -> void:
	print("HAKO_TWO_ASSET_BOOT")

	var extension: Resource = load("res://addons/hakoniwa/hakoniwa.gdextension")
	if extension == null:
		print("HAKO_TWO_ASSET_EXTENSION_LOAD_FAILED")
		get_tree().quit(2)
		return

	var sim_script = load("res://addons/hakoniwa/scripts/hakoniwa_simulation_node.gd")
	var callbacks_script = load("res://two_asset_callbacks.gd")
	if sim_script == null or callbacks_script == null:
		print("HAKO_TWO_ASSET_SCRIPT_LOAD_FAILED")
		get_tree().quit(2)
		return

	_sim = sim_script.new()
	add_child(_sim)
	_sim.asset_name = "godot_core_pro_plant"
	_sim.delta_time_usec = 20000
	_sim.enable_physics_time_sync = false
	_sim.use_internal_shm_endpoint = true
	_sim.shm_endpoint_config_path = "res://config/endpoint_shm_with_pdu.json"
	_sim.simulation_started.connect(_on_simulation_started)
	_sim.simulation_stopped.connect(_on_simulation_stopped)
	_sim.simulation_reset.connect(_on_simulation_reset)
	_sim.simulation_step.connect(_on_simulation_step)

	var initialize_result: int = _sim.initialize()
	if initialize_result != 0:
		print("HAKO_TWO_ASSET_INITIALIZE_FAILED")
		print(_sim.get_last_error_text())
		get_tree().quit(2)
		return

	_motor_endpoint = _sim.get_typed_endpoint("Robot", "motor")
	_pos_endpoint = _sim.get_typed_endpoint("Robot", "pos")
	if _motor_endpoint == null or _pos_endpoint == null:
		print("HAKO_TWO_ASSET_ENDPOINT_BIND_FAILED")
		print(_sim.get_last_error_text())
		get_tree().quit(2)
		return

	var endpoint = _sim.get_endpoint()
	if endpoint == null:
		print("HAKO_TWO_ASSET_ENDPOINT_ACCESS_FAILED")
		print(_sim.get_last_error_text())
		get_tree().quit(2)
		return
	_motor_subscription_id = endpoint.create_subscription_typed("Robot", "motor", Callable(self, "_on_motor_message"))
	if _motor_subscription_id < 0:
		print("HAKO_TWO_ASSET_SUBSCRIBE_MOTOR_FAILED")
		print(endpoint.get_last_error_text())
		get_tree().quit(2)
		return

	_callbacks = callbacks_script.new(_pos_endpoint)
	_sim.set_callbacks(_callbacks)

	print("HAKO_TWO_ASSET_READY")

	var start_result: int = _sim.request_start()
	if start_result != 0:
		print("HAKO_TWO_ASSET_REQUEST_START_FAILED")
		print(_sim.get_last_error_text())
		get_tree().quit(2)

func _on_simulation_step(_simtime_usec: int, world_time_usec: int) -> void:
	if _sim == null or _completed:
		return

	var next_index := _step_count + 1
	var pos_dict: Dictionary = {
		"linear": {
			"x": float(next_index),
			"y": float(next_index + 1),
			"z": float(next_index + 2)
		},
		"angular": {
			"x": 0.0,
			"y": 0.0,
			"z": 0.0
		}
	}
	var send_result: int = _pos_endpoint.send_dict(pos_dict)
	if send_result != 0:
		print("HAKO_TWO_ASSET_SEND_POS_FAILED")
		var endpoint = _sim.get_endpoint()
		if endpoint != null and endpoint.has_method("get_last_error_text"):
			print(endpoint.get_last_error_text())
		else:
			print(_sim.get_last_error_text())
		get_tree().quit(2)
		return

	_step_count = next_index
	print("HAKO_TWO_ASSET_STEP:%d simtime=%d world=%d pos=%s" % [
		_step_count,
		_sim.get_simtime_usec(),
		world_time_usec,
		JSON.stringify(pos_dict)
	])

	if _step_count >= STEP_TARGET:
		_completed = true
		print("HAKO_TWO_ASSET_OK")
		get_tree().quit(0)

func _on_simulation_started() -> void:
	print("HAKO_TWO_ASSET_START_FEEDBACK_OK")

func _on_simulation_stopped() -> void:
	print("HAKO_TWO_ASSET_STOP_FEEDBACK_OK")

func _on_simulation_reset() -> void:
	print("HAKO_TWO_ASSET_RESET_FEEDBACK_OK")

func _on_motor_message(message) -> void:
	if message == null:
		return
	if not message.has_method("to_dict"):
		return
	_latest_motor = message.to_dict()
	print("HAKO_TWO_ASSET_RECV_MOTOR:%s" % JSON.stringify(_latest_motor))
