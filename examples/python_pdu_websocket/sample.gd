extends Node

@onready var endpoint: HakoniwaEndpointNode = $"../HakoniwaEndpointNode"

var _motor_endpoint = null
var _pos_endpoint = null
var _pos_subscription_id := -1
var _send_count := 0
var _send_timer := 0.0
var _endpoint_ready := false


func _ready() -> void:
	if endpoint == null:
		push_error("HakoniwaEndpointNode is required")
		return
	if endpoint.message_script_roots.is_empty():
		endpoint.message_script_roots = PackedStringArray([
			"res://addons/hakoniwa_msgs"
		])
	if not endpoint.has_codec("geometry_msgs", "Twist"):
		if not endpoint.load_codec_plugin("res://addons/hakoniwa/codecs/geometry_msgs_codec"):
			push_error(endpoint.get_last_error_text())
			return
	if endpoint.message_script_roots.is_empty():
    	endpoint.message_script_roots = PackedStringArray([
                "res://addons/hakoniwa_msgs"
    ])
	endpoint.endpoint_ready.connect(_on_endpoint_ready)


func _on_endpoint_ready() -> void:
	_motor_endpoint = endpoint.get_typed_endpoint("Robot", "motor")
	_pos_endpoint = endpoint.get_typed_endpoint("Robot", "pos")
	if _motor_endpoint == null or _pos_endpoint == null:
		push_error(endpoint.get_last_error_text())
		return

	_pos_subscription_id = endpoint.create_subscription_typed(
		"Robot",
		"pos",
		Callable(self, "_on_pos_message"))
	if _pos_subscription_id < 0:
		push_error(endpoint.get_last_error_text())
		return

	_endpoint_ready = true
	print("websocket endpoint ready")


func _process(delta: float) -> void:
	if endpoint == null:
		return

	if not _endpoint_ready or _motor_endpoint == null or not endpoint.is_running():
		return

	endpoint.dispatch_recv_events()

	_send_timer += delta
	if _send_timer < 1.0:
		return
	_send_timer = 0.0

	var motor_dict := {
		"linear": {
			"x": float(_send_count + 1001),
			"y": float(_send_count + 1002),
			"z": float(_send_count + 1003)
		},
		"angular": {
			"x": 0.0,
			"y": 0.0,
			"z": 0.0
		}
	}
	var send_ret: int = _motor_endpoint.send_dict(motor_dict)
	if send_ret == 0:
		print("motor=%s" % JSON.stringify(motor_dict))
		_send_count += 1
	else:
		push_error(endpoint.get_last_error_text())


func _exit_tree() -> void:
	if endpoint == null:
		return
	endpoint.stop_endpoint()
	endpoint.close_endpoint()


func _on_pos_message(message) -> void:
	if message == null:
		return
	if not message.has_method("to_dict"):
		return
	print("pos=%s" % JSON.stringify(message.to_dict()))
