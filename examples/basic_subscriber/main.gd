extends Node

const HakoniwaEndpointNode = preload("res://addons/hakoniwa/scripts/hakoniwa_pdu_endpoint.gd")
const HakoPduStdMsgsUInt64 = preload("res://addons/hakoniwa_msgs/std_msgs/UInt64.gd")

func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)

func expect_equal(actual, expected, label: String) -> void:
	if actual != expected:
		fail("%s: expected=%s actual=%s" % [label, str(expected), str(actual)])

func instantiate_node(script_class, label: String) -> Node:
	var node := script_class.new() as Node
	if node == null:
		fail("%s could not be instantiated" % label)
		return null
	add_child(node)
	return node

func _ready() -> void:
	var extension: Resource = load("res://addons/hakoniwa/hakoniwa.gdextension")
	if extension == null:
		fail("hakoniwa.gdextension could not be loaded")
		return

	if not ClassDB.class_exists("HakoniwaPduEndpoint"):
		fail("HakoniwaPduEndpoint is not registered")
		return

	if not ClassDB.class_exists("HakoniwaCodecRegistry"):
		fail("HakoniwaCodecRegistry is not registered")
		return

	_run_codec_demo()
	_run_latest_demo()
	_run_queue_demo()
	_run_typed_demo()
	_run_complex_typed_demo()
	_run_varray_typed_demo()
	_run_twist_pair_demo()

	print("HAKONIWA_CODEC_SMOKE_OK")

func _create_endpoint_node(config: String) -> Node:
	var hako_codec_extension: Resource = load("res://addons/hakoniwa/codecs/hako_msgs_codec.gdextension")
	if hako_codec_extension == null:
		fail("hako_msgs_codec.gdextension could not be loaded")
		return

	var std_codec_extension: Resource = load("res://addons/hakoniwa/codecs/std_msgs_codec.gdextension")
	if std_codec_extension == null:
		fail("std_msgs_codec.gdextension could not be loaded")
		return

	var geometry_codec_extension: Resource = load("res://addons/hakoniwa/codecs/geometry_msgs_codec.gdextension")
	if geometry_codec_extension == null:
		fail("geometry_msgs_codec.gdextension could not be loaded")
		return

	var endpoint := instantiate_node(HakoniwaEndpointNode, "HakoniwaEndpointNode")
	if endpoint == null:
		return null

	endpoint.config_path = config
	endpoint.codec_plugins = PackedStringArray([
		"res://addons/hakoniwa/codecs/hako_msgs_codec",
		"res://addons/hakoniwa/codecs/std_msgs_codec",
		"res://addons/hakoniwa/codecs/geometry_msgs_codec"
	])
	expect_equal(endpoint.load_configured_codecs(), 3, "codec.load_configured")
	expect_equal(endpoint.has_codec("hako_msgs", "GameControllerOperation"), true, "codec.has_codec.hako_msgs")
	expect_equal(endpoint.has_codec("std_msgs", "UInt64"), true, "codec.has_codec.std_msgs")
	expect_equal(endpoint.has_codec("geometry_msgs", "Pose"), true, "codec.has_codec.geometry_msgs")
	return endpoint

func _run_codec_demo() -> void:
	var endpoint := _create_endpoint_node("")
	if endpoint == null:
		return

	var encoded: PackedByteArray = endpoint.encode_message(
		"hako_msgs",
		"GameControllerOperation",
		{
			"axis": PackedFloat64Array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0]),
			"button": [true, false, true, false, true, false, true, false, true, false, true, false, true, false, true]
		})
	if encoded.is_empty():
		fail("codec.encode returned empty payload")
		return

	var decoded: Dictionary = endpoint.decode_payload("hako_msgs", "GameControllerOperation", encoded)
	expect_equal(Array(decoded["axis"]), [1.0, 2.0, 3.0, 4.0, 5.0, 6.0], "codec.axis")
	expect_equal(Array(decoded["button"]),
		[true, false, true, false, true, false, true, false, true, false, true, false, true, false, true],
		"codec.button")
	endpoint.queue_free()

func _run_latest_demo() -> void:
	var endpoint := _create_endpoint_node("res://config/endpoint_internal_with_pdu.json")
	if endpoint == null:
		return

	print(endpoint.get_backend_name())
	print(endpoint.probe_native_backend())
	print(endpoint.open_endpoint())
	print(endpoint.start_endpoint())
	print(endpoint.send_message("drone0", "sample_state", "std_msgs", "UInt64", {"data": 72623859790382856}))

	var received: Dictionary = endpoint.recv_raw("drone0", "sample_state")
	print(received)
	var decoded: Dictionary = endpoint.recv_message("drone0", "sample_state", "std_msgs", "UInt64")
	print(decoded)
	expect_equal(decoded["value"]["data"], 72623859790382856, "latest.decode.std_msgs.UInt64")

	print(endpoint.is_running())

	endpoint.stop_endpoint()
	endpoint.close_endpoint()
	endpoint.queue_free()

func _run_twist_pair_demo() -> void:
	var endpoint := _create_endpoint_node("res://config/endpoint_internal_with_pdu.json")
	if endpoint == null:
		return

	print(endpoint.open_endpoint())
	print(endpoint.start_endpoint())

	var motor_endpoint = endpoint.get_typed_endpoint("drone0", "motor")
	var pos_endpoint = endpoint.get_typed_endpoint("drone0", "pos")
	if motor_endpoint == null or pos_endpoint == null:
		fail(endpoint.get_last_error_text())
		return

	var motor = endpoint.to_typed_value("geometry_msgs", "Twist", {
		"linear": {
			"x": 1001.0,
			"y": 1002.0,
			"z": 1003.0
		},
		"angular": {
			"x": 0.0,
			"y": 0.0,
			"z": 0.0
		}
	})
	var pos = endpoint.to_typed_value("geometry_msgs", "Twist", {
		"linear": {
			"x": 1.0,
			"y": 2.0,
			"z": 3.0
		},
		"angular": {
			"x": 0.0,
			"y": 0.0,
			"z": 0.0
		}
	})

	print(motor_endpoint.send(motor))
	print(pos_endpoint.send(pos))

	var motor_record: Dictionary = motor_endpoint.recv_record()
	var pos_record: Dictionary = pos_endpoint.recv_record()
	print(motor_record)
	print(pos_record)

	expect_equal(motor_record["value"]["linear"]["x"], 1001.0, "twist.motor.record.linear.x")
	expect_equal(motor_record["value"]["linear"]["z"], 1003.0, "twist.motor.record.linear.z")
	expect_equal(pos_record["value"]["linear"]["x"], 1.0, "twist.pos.record.linear.x")
	expect_equal(pos_record["value"]["linear"]["z"], 3.0, "twist.pos.record.linear.z")

	var motor_recv = motor_endpoint.recv()
	var pos_recv = pos_endpoint.recv()
	var motor_dict: Dictionary = motor_recv.to_dict()
	var pos_dict: Dictionary = pos_recv.to_dict()
	expect_equal(motor_dict["linear"]["y"], 1002.0, "twist.motor.typed.linear.y")
	expect_equal(pos_dict["linear"]["y"], 2.0, "twist.pos.typed.linear.y")

	endpoint.stop_endpoint()
	endpoint.close_endpoint()
	endpoint.queue_free()

func _run_queue_demo() -> void:
	var queue_endpoint := _create_endpoint_node("res://config/endpoint_internal_queue_with_pdu.json")
	if queue_endpoint == null:
		return

	print(queue_endpoint.open_endpoint())
	print(queue_endpoint.start_endpoint())
	print(queue_endpoint.set_recv_event("drone0", 0))
	print(queue_endpoint.send_message("drone0", "sample_state", "std_msgs", "UInt64", {"data": 10}))
	print(queue_endpoint.send_message("drone0", "sample_state", "std_msgs", "UInt64", {"data": 11}))
	print(queue_endpoint.send_message("drone0", "sample_state", "std_msgs", "UInt64", {"data": 12}))
	print(queue_endpoint.get_pending_count())

	var first: Dictionary = queue_endpoint.recv_next_raw()
	print(first)
	print(queue_endpoint.decode_record("std_msgs", "UInt64", first))
	print(queue_endpoint.get_pending_count())
	var second: Dictionary = queue_endpoint.recv_next_raw()
	print(second)
	print(queue_endpoint.decode_record("std_msgs", "UInt64", second))
	print(queue_endpoint.get_pending_count())
	var third: Dictionary = queue_endpoint.recv_next_raw()
	print(third)
	print(queue_endpoint.decode_record("std_msgs", "UInt64", third))
	expect_equal(queue_endpoint.decode_record("std_msgs", "UInt64", first)["value"]["data"], 10, "queue.decode.1")
	expect_equal(queue_endpoint.decode_record("std_msgs", "UInt64", second)["value"]["data"], 11, "queue.decode.2")
	expect_equal(queue_endpoint.decode_record("std_msgs", "UInt64", third)["value"]["data"], 12, "queue.decode.3")
	print(queue_endpoint.get_pending_count())
	print(queue_endpoint.recv_next_raw())

	queue_endpoint.stop_endpoint()
	queue_endpoint.close_endpoint()
	queue_endpoint.queue_free()

func _run_typed_demo() -> void:
	var endpoint := _create_endpoint_node("res://config/endpoint_internal_with_pdu.json")
	if endpoint == null:
		return

	print(endpoint.open_endpoint())
	print(endpoint.start_endpoint())

	var typed_endpoint = endpoint.get_typed_endpoint("drone0", "sample_state")
	if typed_endpoint == null:
		fail(endpoint.get_last_error_text())
		return

	var typed_value := HakoPduStdMsgsUInt64.new()
	typed_value.data = 42
	print(typed_endpoint.send(typed_value))

	var typed_record: Dictionary = typed_endpoint.recv_record()
	print(typed_record)
	var typed_recv = typed_endpoint.recv()
	expect_equal(typed_record["typed_value"].data, 42, "typed.record.std_msgs.UInt64")
	expect_equal(typed_recv.data, 42, "typed.recv.std_msgs.UInt64")

	endpoint.stop_endpoint()
	endpoint.close_endpoint()
	endpoint.queue_free()

func _run_complex_typed_demo() -> void:
	var endpoint := _create_endpoint_node("res://config/endpoint_internal_with_pdu.json")
	if endpoint == null:
		return

	print(endpoint.open_endpoint())
	print(endpoint.start_endpoint())

	var pose_endpoint = endpoint.get_typed_endpoint("drone0", "sample_pose")
	if pose_endpoint == null:
		fail(endpoint.get_last_error_text())
		return

	var pose = endpoint.to_typed_value("geometry_msgs", "Pose", {
		"position": {
			"x": 1.25,
			"y": 2.5,
			"z": 3.75
		},
		"orientation": {
			"x": 0.0,
			"y": 0.5,
			"z": 0.0,
			"w": 1.0
		}
	})
	print(pose_endpoint.send(pose))

	var pose_record: Dictionary = pose_endpoint.recv_record()
	print(pose_record)
	expect_equal(pose_record["value"]["position"]["x"], 1.25, "pose.record.position.x")
	expect_equal(pose_record["value"]["orientation"]["y"], 0.5, "pose.record.orientation.y")

	var pose_recv = pose_endpoint.recv()
	var pose_dict: Dictionary = pose_recv.to_dict()
	expect_equal(pose_dict["position"]["x"], 1.25, "pose.typed.position.x")
	expect_equal(pose_dict["position"]["y"], 2.5, "pose.typed.position.y")
	expect_equal(pose_dict["position"]["z"], 3.75, "pose.typed.position.z")
	expect_equal(pose_dict["orientation"]["y"], 0.5, "pose.typed.orientation.y")
	expect_equal(pose_dict["orientation"]["w"], 1.0, "pose.typed.orientation.w")

	endpoint.stop_endpoint()
	endpoint.close_endpoint()
	endpoint.queue_free()

func _run_varray_typed_demo() -> void:
	var endpoint := _create_endpoint_node("res://config/endpoint_internal_with_pdu.json")
	if endpoint == null:
		return

	print(endpoint.open_endpoint())
	print(endpoint.start_endpoint())

	var multi_endpoint = endpoint.get_typed_endpoint("drone0", "sample_multi")
	if multi_endpoint == null:
		fail(endpoint.get_last_error_text())
		return

	var multi = endpoint.to_typed_value("std_msgs", "UInt64MultiArray", {
		"layout": {
			"dim": [
				{"label": "rows", "size": 2, "stride": 6},
				{"label": "cols", "size": 3, "stride": 3}
			],
			"data_offset": 0
		},
		"data": [100, 101, 102, 200, 201, 202]
	})
	print(multi_endpoint.send(multi))

	var multi_record: Dictionary = multi_endpoint.recv_record()
	print(multi_record)
	expect_equal(multi_record["value"]["layout"]["dim"][0]["label"], "rows", "multi.record.layout.dim0.label")
	expect_equal(multi_record["value"]["layout"]["dim"][1]["size"], 3, "multi.record.layout.dim1.size")
	expect_equal(Array(multi_record["value"]["data"]), [100, 101, 102, 200, 201, 202], "multi.record.data")

	var multi_recv = multi_endpoint.recv()
	var multi_dict: Dictionary = multi_recv.to_dict()
	expect_equal(multi_dict["layout"]["dim"][0]["stride"], 6, "multi.typed.layout.dim0.stride")
	expect_equal(multi_dict["layout"]["dim"][1]["label"], "cols", "multi.typed.layout.dim1.label")
	expect_equal(Array(multi_dict["data"]), [100, 101, 102, 200, 201, 202], "multi.typed.data")

	endpoint.stop_endpoint()
	endpoint.close_endpoint()
	endpoint.queue_free()
