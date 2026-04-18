extends Node

@onready var sim: HakoniwaSimNode = $"../HakoniwaSimNode"
var _motor_endpoint = null
var _pos_endpoint = null
var _motor_subscription_id := -1
var _send_count := 0

func _ready() -> void:
	sim.simulation_ready.connect(_on_simulation_ready)
	sim.simulation_started.connect(_on_simulation_started)
	sim.simulation_stopped.connect(_on_simulation_stopped)
	sim.simulation_reset.connect(_on_simulation_reset)
	sim.simulation_step.connect(_on_simulation_step)

func _on_simulation_ready() -> void:
	var endpoint = sim.get_endpoint()
	if endpoint == null:
		push_error(sim.get_last_error_text())
		return
	var motor_ret = endpoint.create_pdu_lchannel("Robot", "motor")
	var pos_ret = endpoint.create_pdu_lchannel("Robot", "pos")
	print("INFO: create motor pdu channel: ret = ", motor_ret)
	print("INFO: create pos pdu channel: ret = ", pos_ret)
	_motor_endpoint = sim.get_typed_endpoint("Robot", "motor")
	_pos_endpoint = sim.get_typed_endpoint("Robot", "pos")
	if _motor_endpoint == null or _pos_endpoint == null:
		print("sample endpoint bind failed")
		print(sim.get_last_error_text())
		return

	_motor_subscription_id = endpoint.create_subscription_typed(
		"Robot",
		"motor",
		Callable(self, "_on_motor_message"))
	if _motor_subscription_id < 0:
		print("sample subscribe failed")
		print(endpoint.get_last_error_text())
		return

func _on_simulation_started() -> void:
	print("simulation started")

func _on_simulation_stopped() -> void:
	print("simulation stopped")

func _on_simulation_reset() -> void:
	print("simulation reset")

func _on_simulation_step(simtime_usec: int, world_time_usec: int) -> void:
	if _pos_endpoint != null:
		var pos_dict := {
			"linear": {
				"x": float(_send_count),
				"y": float(_send_count + 1),
				"z": float(_send_count + 2)
			},
			"angular": {
				"x": 0.0,
				"y": 0.0,
				"z": 0.0
			}
		}
		if (_send_count % 2) == 0:
			var send_ret: int = _pos_endpoint.send_dict(pos_dict)
			if send_ret == 0:
				print("pos=%s" % JSON.stringify(pos_dict))
			else:
				print("sample pos send failed: ", send_ret)
				print(sim.get_last_error_text())
		_send_count = _send_count + 1
	print("step simtime=%d world=%d" % [simtime_usec, world_time_usec])

func _on_motor_message(message) -> void:
	if message == null:
		return
	if not message.has_method("to_dict"):
		return
	print("motor=%s" % JSON.stringify(message.to_dict()))
