extends Node

func _ready() -> void:
	var extension: Resource = load("res://addons/hakoniwa/hakoniwa.gdextension")
	if extension == null:
		push_error("hakoniwa.gdextension could not be loaded")
		return

	if not ClassDB.class_exists("HakoniwaPduEndpoint"):
		push_error("HakoniwaPduEndpoint is not registered")
		return

	var endpoint := ClassDB.instantiate("HakoniwaPduEndpoint") as Node
	if endpoint == null:
		push_error("HakoniwaPduEndpoint could not be instantiated")
		return

	add_child(endpoint)

	print(endpoint.call("get_backend_name"))
	print(endpoint.call("probe_native_backend"))
	print(endpoint.call("open", "res://config/endpoint_internal_with_pdu.json"))
	print(endpoint.call("start"))

	var payload := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
	print(endpoint.call("send_by_name", "drone0", "sample_state", payload))
	print(endpoint.call("recv_by_name", "drone0", "sample_state"))
	print(endpoint.call("is_running"))

	endpoint.call("stop")
	endpoint.call("close")
	endpoint.queue_free()

	_run_queue_demo()

func _run_queue_demo() -> void:
	var queue_endpoint := ClassDB.instantiate("HakoniwaPduEndpoint") as Node
	if queue_endpoint == null:
		push_error("HakoniwaPduEndpoint could not be instantiated for queue demo")
		return

	add_child(queue_endpoint)

	print(queue_endpoint.call("open", "res://config/endpoint_internal_queue_with_pdu.json"))
	print(queue_endpoint.call("start"))
	print(queue_endpoint.call("set_recv_event", "drone0", 0))

	var payload_a1 := PackedByteArray([10])
	var payload_b := PackedByteArray([11])
	var payload_a2 := PackedByteArray([12])

	print(queue_endpoint.call("send_by_name", "drone0", "sample_state", payload_a1))
	print(queue_endpoint.call("send_by_name", "drone0", "sample_state", payload_b))
	print(queue_endpoint.call("send_by_name", "drone0", "sample_state", payload_a2))
	print(queue_endpoint.call("get_pending_count"))

	print(queue_endpoint.call("recv_next"))
	print(queue_endpoint.call("get_pending_count"))
	print(queue_endpoint.call("recv_next"))
	print(queue_endpoint.call("get_pending_count"))
	print(queue_endpoint.call("recv_next"))
	print(queue_endpoint.call("get_pending_count"))
	print(queue_endpoint.call("recv_next"))

	queue_endpoint.call("stop")
	queue_endpoint.call("close")
	queue_endpoint.queue_free()
