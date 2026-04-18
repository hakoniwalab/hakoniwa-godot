class_name HakoniwaEndpointNode
extends Node

const HakoniwaTypedEndpoint = preload("res://addons/hakoniwa/scripts/hakoniwa_typed_endpoint.gd")

signal raw_message_received(subscription_id, record)
signal message_received(subscription_id, message, record)
signal typed_message_received(subscription_id, typed_value, record)

@export var config_path: String = ""
@export var codec_plugins: PackedStringArray = []
@export var message_script_roots: PackedStringArray = PackedStringArray([
	"res://addons/hakoniwa_msgs"
])
@export var endpoint_name: String = "hakoniwa_godot_endpoint"
@export var direction: int = 2
@export var auto_open_on_ready: bool = false
@export var auto_start_on_ready: bool = false
@export var auto_process_recv_events: bool = false
@export var auto_close_on_exit: bool = true

var _endpoint: Node = null
var _codecs: Node = null
var _last_error_text: String = ""
var _typed_binding_cache: Dictionary = {}
var _codec_extension_resources: Array = []
var _subscriptions: Dictionary = {}
var _registered_recv_keys: Dictionary = {}
var _next_subscription_id: int = 1

func _ready() -> void:
	if not _ensure_native_nodes():
		push_error(_last_error_text)
		return
	if codec_plugins.size() > 0 and load_configured_codecs() != codec_plugins.size():
		push_error(_last_error_text)
		return
	if auto_open_on_ready and not config_path.is_empty():
		if open_endpoint() != 0:
			push_error(_last_error_text)
			return
		if auto_start_on_ready and start_endpoint() != 0:
			push_error(_last_error_text)

func _process(_delta: float) -> void:
	if auto_process_recv_events and _endpoint != null and is_running():
		if _subscriptions.is_empty():
			process_recv_events()
		else:
			dispatch_recv_events()

func _exit_tree() -> void:
	if not auto_close_on_exit:
		return
	stop_endpoint()
	close_endpoint()

func get_last_error_text() -> String:
	return _last_error_text

func get_last_error_code() -> int:
	if _endpoint == null:
		return -1
	return _endpoint.get_last_error()

func get_backend_name() -> String:
	if not _ensure_endpoint():
		return ""
	return _endpoint.get_backend_name()

func probe_native_backend() -> bool:
	if not _ensure_endpoint():
		return false
	return _endpoint.probe_native_backend()

func open_endpoint(path: String = "") -> int:
	if not _ensure_endpoint():
		return -1
	var resolved_path := path
	if resolved_path.is_empty():
		resolved_path = config_path
	else:
		config_path = resolved_path
	_endpoint.endpoint_name = endpoint_name
	_endpoint.direction = direction
	var result: int = _endpoint.open(resolved_path)
	_update_endpoint_error("open_endpoint")
	return result

func close_endpoint() -> void:
	if _endpoint == null:
		return
	_endpoint.close()
	_update_endpoint_error("close_endpoint")

func start_endpoint() -> int:
	if not _ensure_endpoint():
		return -1
	var result: int = _endpoint.start()
	_update_endpoint_error("start_endpoint")
	return result

func post_start_endpoint() -> int:
	if not _ensure_endpoint():
		return -1
	var result: int = _endpoint.post_start()
	_update_endpoint_error("post_start_endpoint")
	return result

func stop_endpoint() -> void:
	if _endpoint == null:
		return
	_endpoint.stop()
	_update_endpoint_error("stop_endpoint")

func process_recv_events() -> void:
	if _endpoint == null:
		return
	_endpoint.process_recv_events()

func dispatch_recv_events() -> int:
	if _subscriptions.is_empty():
		return 0
	process_recv_events()
	var dispatched := 0
	while true:
		var record: Dictionary = _endpoint.pop_subscribed_record()
		if record.is_empty():
			break
		dispatched += _dispatch_record(record)
	return dispatched

func is_running() -> bool:
	if not _ensure_endpoint():
		return false
	var running: bool = _endpoint.is_running()
	_update_endpoint_error("is_running")
	return running

func set_recv_event(robot: String, channel_id: int) -> int:
	if not _ensure_endpoint():
		return -1
	var result: int = _endpoint.set_recv_event(robot, channel_id)
	_update_endpoint_error("set_recv_event")
	return result

func get_pending_count() -> int:
	if not _ensure_endpoint():
		return 0
	var count: int = _endpoint.get_pending_count()
	_update_endpoint_error("get_pending_count")
	return count

func create_pdu_lchannel(robot: String, pdu_name: String) -> int:
	if not _ensure_endpoint():
		return -1
	var result: int = _endpoint.create_pdu_lchannel_by_name(robot, pdu_name)
	_update_endpoint_error("create_pdu_lchannel")
	return result

func recv_raw(robot: String, pdu_name: String) -> Dictionary:
	if not _ensure_endpoint():
		return {}
	var record: Dictionary = _endpoint.recv_by_name(robot, pdu_name)
	_update_endpoint_error("recv_raw")
	return record

func recv_next_raw() -> Dictionary:
	if not _ensure_endpoint():
		return {}
	var record: Dictionary = _endpoint.recv_next()
	_update_endpoint_error("recv_next_raw")
	return record

func send_raw(robot: String, pdu_name: String, payload: PackedByteArray) -> int:
	if not _ensure_endpoint():
		return -1
	var result: int = _endpoint.send_by_name(robot, pdu_name, payload)
	_update_endpoint_error("send_raw")
	return result

func create_subscription_raw(robot: String, pdu_name: String, callback: Callable = Callable()) -> int:
	var binding := _resolve_typed_binding(robot, pdu_name)
	if binding.is_empty():
		return -1
	return _create_subscription(binding, "raw", callback)

func create_subscription_message(robot: String,
		pdu_name: String,
		package_name: String,
		message_name: String,
		callback: Callable = Callable()) -> int:
	var binding := _resolve_typed_binding(robot, pdu_name)
	if binding.is_empty():
		return -1
	if binding["package_name"] != package_name or binding["message_name"] != message_name:
		_last_error_text = "create_subscription_message failed: type mismatch for %s/%s" % [robot, pdu_name]
		return -1
	return _create_subscription(binding, "message", callback)

func create_subscription_typed(robot: String, pdu_name: String, callback: Callable = Callable()) -> int:
	var binding := _resolve_typed_binding(robot, pdu_name)
	if binding.is_empty():
		return -1
	return _create_subscription(binding, "typed", callback)

func destroy_subscription(subscription_id: int) -> bool:
	if not _subscriptions.has(subscription_id):
		_last_error_text = "destroy_subscription failed: subscription not found"
		return false
	_subscriptions.erase(subscription_id)
	_last_error_text = ""
	return true

func load_codec_plugin(plugin_path: String) -> bool:
	if not _ensure_codecs():
		return false
	if not _load_codec_gdextension(plugin_path):
		return false
	var loaded: bool = _codecs.load_plugin(plugin_path)
	_update_codec_error("load_codec_plugin")
	return loaded

func load_configured_codecs() -> int:
	if not _ensure_codecs():
		return 0
	var loaded_count := 0
	for plugin_path in codec_plugins:
		if not load_codec_plugin(plugin_path):
			return loaded_count
		loaded_count += 1
	return loaded_count

func has_codec(package_name: String, message_name: String) -> bool:
	if not _ensure_codecs():
		return false
	return _codecs.has_codec(package_name, message_name)

func encode_message(package_name: String, message_name: String, value: Dictionary) -> PackedByteArray:
	if not _ensure_codecs():
		return PackedByteArray()
	var payload: PackedByteArray = _codecs.encode(package_name, message_name, value)
	_update_codec_error("encode_message")
	return payload

func encode_typed_message(package_name: String, message_name: String, typed_value: Variant) -> PackedByteArray:
	if typed_value == null:
		_last_error_text = "encode_typed_message failed: typed_value is null"
		return PackedByteArray()
	if not typed_value.has_method("to_dict"):
		_last_error_text = "encode_typed_message failed: typed_value has no to_dict()"
		return PackedByteArray()
	var value: Variant = typed_value.call("to_dict")
	if typeof(value) != TYPE_DICTIONARY:
		_last_error_text = "encode_typed_message failed: to_dict() did not return Dictionary"
		return PackedByteArray()
	return encode_message(package_name, message_name, value)

func decode_payload(package_name: String, message_name: String, payload: PackedByteArray) -> Dictionary:
	if not _ensure_codecs():
		return {}
	var value: Dictionary = _codecs.decode(package_name, message_name, payload)
	_update_codec_error("decode_payload")
	return value

func decode_record(package_name: String, message_name: String, record: Dictionary) -> Dictionary:
	if record.is_empty() or not record.has("payload"):
		return {}
	var value: Dictionary = decode_payload(package_name, message_name, record["payload"])
	if value.is_empty():
		return {}
	return {
		"robot": record.get("robot", ""),
		"channel_id": record.get("channel_id", -1),
		"pdu_name": record.get("pdu_name", ""),
		"timestamp_ns": record.get("timestamp_ns", 0),
		"value": value
	}

func to_typed_value(package_name: String, message_name: String, value: Dictionary) -> Variant:
	var script := _load_message_script(package_name, message_name)
	if script == null:
		return null
	if not script.has_method("from_dict"):
		_last_error_text = "typed message script has no from_dict(): %s/%s" % [package_name, message_name]
		return null
	_last_error_text = ""
	return script.call("from_dict", value)

func decode_typed_record(package_name: String, message_name: String, record: Dictionary) -> Dictionary:
	var decoded := decode_record(package_name, message_name, record)
	if decoded.is_empty():
		return {}
	var typed_value := to_typed_value(package_name, message_name, decoded["value"])
	if typed_value == null:
		return {}
	decoded["typed_value"] = typed_value
	return decoded

func send_message(robot: String,
		pdu_name: String,
		package_name: String,
		message_name: String,
		value: Dictionary) -> int:
	var payload := encode_message(package_name, message_name, value)
	if payload.is_empty():
		return -1
	return send_raw(robot, pdu_name, payload)

func recv_message(robot: String, pdu_name: String, package_name: String, message_name: String) -> Dictionary:
	return decode_record(package_name, message_name, recv_raw(robot, pdu_name))

func recv_next_message(package_name: String, message_name: String) -> Dictionary:
	return decode_record(package_name, message_name, recv_next_raw())

func send_typed_message(robot: String,
		pdu_name: String,
		package_name: String,
		message_name: String,
		typed_value: Variant) -> int:
	var payload := encode_typed_message(package_name, message_name, typed_value)
	if payload.is_empty():
		return -1
	return send_raw(robot, pdu_name, payload)

func recv_typed_message(robot: String, pdu_name: String, package_name: String, message_name: String) -> Dictionary:
	return decode_typed_record(package_name, message_name, recv_raw(robot, pdu_name))

func recv_next_typed_message(package_name: String, message_name: String) -> Dictionary:
	return decode_typed_record(package_name, message_name, recv_next_raw())

func get_typed_endpoint(robot: String, pdu_name: String) -> Variant:
	var binding: Dictionary = _resolve_typed_binding(robot, pdu_name)
	if binding.is_empty():
		return null
	return HakoniwaTypedEndpoint.new().setup(
		self,
		robot,
		pdu_name,
		binding["package_name"],
		binding["message_name"])

func _create_subscription(binding: Dictionary, delivery_kind: String, callback: Callable) -> int:
	var register_key := "%s::%d" % [binding["robot"], binding["channel_id"]]
	if not _registered_recv_keys.has(register_key):
		var register_result: int = _endpoint.subscribe_on_recv_callback_by_name(
			binding["robot"],
			binding["pdu_name"])
		_update_endpoint_error("create_subscription.subscribe_on_recv_callback_by_name")
		if register_result != 0:
			return -1
		_registered_recv_keys[register_key] = true
	var subscription_id := _next_subscription_id
	_next_subscription_id += 1
	var subscription := binding.duplicate()
	subscription["delivery_kind"] = delivery_kind
	subscription["callback"] = callback
	_subscriptions[subscription_id] = subscription
	_last_error_text = ""
	return subscription_id

func _dispatch_record(record: Dictionary) -> int:
	var robot: String = record.get("robot", "")
	var channel_id: int = record.get("channel_id", -1)
	var dispatched := 0
	for subscription_id in _subscriptions.keys():
		var subscription: Dictionary = _subscriptions[subscription_id]
		if subscription.get("robot", "") != robot:
			continue
		if subscription.get("channel_id", -1) != channel_id:
			continue
		var delivery_kind: String = subscription.get("delivery_kind", "raw")
		var callback: Callable = subscription.get("callback", Callable())
		if delivery_kind == "typed":
			var typed_record := decode_typed_record(
				subscription["package_name"],
				subscription["message_name"],
				record)
			if typed_record.is_empty():
				continue
			var typed_value = typed_record.get("typed_value", null)
			if callback.is_valid():
				callback.call(typed_value)
			typed_message_received.emit(subscription_id, typed_value, typed_record)
			dispatched += 1
			continue
		if delivery_kind == "message":
			var decoded_record := decode_record(
				subscription["package_name"],
				subscription["message_name"],
				record)
			if decoded_record.is_empty():
				continue
			var message: Dictionary = decoded_record.get("value", {})
			if callback.is_valid():
				callback.call(message)
			message_received.emit(subscription_id, message, decoded_record)
			dispatched += 1
			continue
		if callback.is_valid():
			callback.call(record)
		raw_message_received.emit(subscription_id, record)
		dispatched += 1
	return dispatched

func _ensure_native_nodes() -> bool:
	return _ensure_endpoint() and _ensure_codecs()

func _ensure_endpoint() -> bool:
	if _endpoint != null:
		return true
	if not ClassDB.class_exists("HakoniwaPduEndpoint"):
		_last_error_text = "HakoniwaPduEndpoint is not registered"
		return false
	_endpoint = ClassDB.instantiate("HakoniwaPduEndpoint") as Node
	if _endpoint == null:
		_last_error_text = "HakoniwaPduEndpoint could not be instantiated"
		return false
	add_child(_endpoint)
	_endpoint.endpoint_name = endpoint_name
	_endpoint.direction = direction
	return true

func _ensure_codecs() -> bool:
	if _codecs != null:
		return true
	if not ClassDB.class_exists("HakoniwaCodecRegistry"):
		_last_error_text = "HakoniwaCodecRegistry is not registered"
		return false
	_codecs = ClassDB.instantiate("HakoniwaCodecRegistry") as Node
	if _codecs == null:
		_last_error_text = "HakoniwaCodecRegistry could not be instantiated"
		return false
	add_child(_codecs)
	return true

func _update_endpoint_error(context: String) -> void:
	if _endpoint == null:
		return
	var code: int = _endpoint.get_last_error()
	if code == 0:
		_last_error_text = ""
	else:
		_last_error_text = "%s failed: error=%d" % [context, code]

func _update_codec_error(context: String) -> void:
	if _codecs == null:
		return
	var error_text: String = _codecs.get_last_error()
	if error_text.is_empty():
		_last_error_text = ""
	else:
		_last_error_text = "%s failed: %s" % [context, error_text]

func _load_codec_gdextension(plugin_path: String) -> bool:
	var gdextension_path := _to_codec_gdextension_path(plugin_path)
	if gdextension_path.is_empty():
		return true
	var extension: Resource = load(gdextension_path)
	if extension == null:
		_last_error_text = "load_codec_gdextension failed: %s" % gdextension_path
		return false
	_codec_extension_resources.append(extension)
	_last_error_text = ""
	return true

func _to_codec_gdextension_path(plugin_path: String) -> String:
	if plugin_path.is_empty():
		return ""
	if plugin_path.ends_with(".gdextension"):
		return plugin_path
	if plugin_path.ends_with(".dylib") or plugin_path.ends_with(".so") or plugin_path.ends_with(".dll"):
		var ext_index := plugin_path.rfind(".")
		if ext_index >= 0:
			return plugin_path.substr(0, ext_index) + ".gdextension"
		return ""
	return plugin_path + ".gdextension"

func _load_message_script(package_name: String, message_name: String) -> GDScript:
	for root in message_script_roots:
		var script_path := "%s/%s/%s.gd" % [root, package_name, message_name]
		var script := load(script_path) as GDScript
		if script != null:
			return script
	_last_error_text = "message script not found: %s/%s" % [package_name, message_name]
	return null

func _resolve_typed_binding(robot: String, pdu_name: String) -> Dictionary:
	var cache_key := "%s::%s" % [robot, pdu_name]
	if _typed_binding_cache.has(cache_key):
		return _typed_binding_cache[cache_key]

	if config_path.is_empty():
		_last_error_text = "typed binding resolution failed: config_path is empty"
		return {}

	var endpoint_config := _read_json_file(config_path)
	if typeof(endpoint_config) != TYPE_DICTIONARY:
		_last_error_text = "typed binding resolution failed: endpoint config could not be read"
		return {}

	var pdu_def_rel: String = endpoint_config.get("pdu_def_path", "")
	if pdu_def_rel.is_empty():
		_last_error_text = "typed binding resolution failed: pdu_def_path is missing"
		return {}

	var config_dir := config_path.get_base_dir()
	var pdu_def_path := _join_res_path(config_dir, pdu_def_rel)
	var pdu_def := _read_json_file(pdu_def_path)
	if typeof(pdu_def) != TYPE_DICTIONARY:
		_last_error_text = "typed binding resolution failed: pdu_def could not be read"
		return {}

	var pdutypes_id := ""
	for robot_entry in pdu_def.get("robots", []):
		if typeof(robot_entry) == TYPE_DICTIONARY and robot_entry.get("name", "") == robot:
			pdutypes_id = robot_entry.get("pdutypes_id", "")
			break

	if pdutypes_id.is_empty():
		_last_error_text = "typed binding resolution failed: robot not found in pdu_def: %s" % robot
		return {}

	var pdutypes_rel := ""
	for path_entry in pdu_def.get("paths", []):
		if typeof(path_entry) == TYPE_DICTIONARY and path_entry.get("id", "") == pdutypes_id:
			pdutypes_rel = path_entry.get("path", "")
			break

	if pdutypes_rel.is_empty():
		_last_error_text = "typed binding resolution failed: pdutypes path not found for id: %s" % pdutypes_id
		return {}

	var pdu_def_dir := pdu_def_path.get_base_dir()
	var pdutypes_path := _join_res_path(pdu_def_dir, pdutypes_rel)
	var pdutypes := _read_json_file(pdutypes_path)
	if typeof(pdutypes) != TYPE_ARRAY:
		_last_error_text = "typed binding resolution failed: pdutypes could not be read"
		return {}

	for pdu_entry in pdutypes:
		if typeof(pdu_entry) != TYPE_DICTIONARY:
			continue
		if pdu_entry.get("name", "") != pdu_name:
			continue
		var type_name: String = pdu_entry.get("type", "")
		if not type_name.contains("/"):
			_last_error_text = "typed binding resolution failed: invalid type name: %s" % type_name
			return {}
		var parts := type_name.split("/", false, 1)
		var binding := {
			"robot": robot,
			"pdu_name": pdu_name,
			"channel_id": pdu_entry.get("channel_id", -1),
			"package_name": parts[0],
			"message_name": parts[1]
		}
		_typed_binding_cache[cache_key] = binding
		_last_error_text = ""
		return binding

	_last_error_text = "typed binding resolution failed: pdu not found: %s" % pdu_name
	return {}

func _read_json_file(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	return JSON.parse_string(text)

func _join_res_path(base_dir: String, child_path: String) -> String:
	if child_path.begins_with("res://") or child_path.begins_with("user://"):
		return child_path
	if base_dir.is_empty():
		return child_path
	if base_dir.ends_with("/"):
		return "%s%s" % [base_dir, child_path]
	return "%s/%s" % [base_dir, child_path]
