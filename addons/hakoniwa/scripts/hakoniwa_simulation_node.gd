class_name HakoniwaSimNode
extends Node

signal simulation_started
signal simulation_stopped
signal simulation_reset

const HakoniwaEndpointNode = preload("res://addons/hakoniwa/scripts/hakoniwa_pdu_endpoint.gd")

const STATE_STOPPED := 0
const STATE_RUNNABLE := 1
const STATE_RUNNING := 2
const STATE_STOPPING := 3
const STATE_RESETTING := 4
const STATE_ERROR := 5
const STATE_TERMINATED := 6

const EVENT_NONE := 0
const EVENT_START := 1
const EVENT_STOP := 2
const EVENT_RESET := 3
const EVENT_ERROR := 4

@export var asset_name: String = ""
@export var use_internal_shm_endpoint: bool = false
@export var shm_endpoint_config_path: String = ""
@export var delta_time_usec: int = 20000
@export var auto_initialize_on_ready: bool = false
@export var auto_unregister_on_exit: bool = true
@export var auto_tick_on_physics_process: bool = false

var _core_asset: Node = null
var _internal_endpoint: Node = null
var _callbacks = null
var _last_error_text: String = ""
var _current_simtime_usec: int = 0

func _ready() -> void:
	if auto_initialize_on_ready:
		var result := initialize()
		if result != 0:
			push_error(_last_error_text)

func _physics_process(_delta: float) -> void:
	if auto_tick_on_physics_process:
		tick()

func _exit_tree() -> void:
	if auto_unregister_on_exit:
		shutdown()

func set_callbacks(callbacks) -> void:
	_callbacks = callbacks

func initialize() -> int:
	if not _ensure_core_asset():
		return -1
	if asset_name.is_empty():
		_last_error_text = "initialize failed: asset_name is empty"
		return -1
	if delta_time_usec <= 0:
		_last_error_text = "initialize failed: delta_time_usec must be > 0"
		return -1
	if use_internal_shm_endpoint:
		if shm_endpoint_config_path.is_empty():
			_last_error_text = "initialize failed: shm_endpoint_config_path is empty"
			return -1
		if not _ensure_internal_endpoint():
			return -1
		var loaded_codecs: int = _internal_endpoint.load_configured_codecs()
		if loaded_codecs != _internal_endpoint.codec_plugins.size():
			_last_error_text = _internal_endpoint.get_last_error_text()
			return -1
		var open_result: int = _internal_endpoint.open_endpoint(shm_endpoint_config_path)
		if open_result != 0:
			_last_error_text = _internal_endpoint.get_last_error_text()
			return open_result
	var result: int = _core_asset.initialize_asset(asset_name)
	_update_error("initialize")
	if result == 0:
		_current_simtime_usec = 0
	return result

func shutdown() -> void:
	if _core_asset == null:
		return
	if _internal_endpoint != null:
		_internal_endpoint.stop_endpoint()
		_internal_endpoint.close_endpoint()
	_core_asset.unregister_asset()
	_update_error("shutdown")
	if _last_error_text.is_empty():
		_current_simtime_usec = 0

func request_start() -> int:
	if not _ensure_core_asset():
		return -1
	var result: int = _core_asset.request_start()
	_update_error("request_start")
	return result

func request_stop() -> int:
	if not _ensure_core_asset():
		return -1
	var result: int = _core_asset.request_stop()
	_update_error("request_stop")
	return result

func request_reset() -> int:
	if not _ensure_core_asset():
		return -1
	var result: int = _core_asset.request_reset()
	_update_error("request_reset")
	return result

func tick() -> bool:
	if not _ensure_core_asset():
		return false

	var event: int = _core_asset.poll_event()
	_update_error("tick.poll_event")
	if event < 0:
		return false

	if event == EVENT_START:
		if _internal_endpoint != null:
			var start_endpoint_result: int = _internal_endpoint.start_endpoint()
			if start_endpoint_result != 0:
				_last_error_text = _internal_endpoint.get_last_error_text()
				return false
			var post_start_endpoint_result: int = _internal_endpoint.post_start_endpoint()
			if post_start_endpoint_result != 0:
				_last_error_text = _internal_endpoint.get_last_error_text()
				return false
		if _callbacks != null:
			_callbacks.on_simulation_start()
		_core_asset.notify_write_pdu_done()
		_update_error("tick.notify_write_pdu_done")
		if not _last_error_text.is_empty():
			return false
		var start_result: int = _core_asset.start_feedback_ok()
		_update_error("tick.start_feedback_ok")
		if start_result == 0:
			simulation_started.emit()
		return false

	if event == EVENT_STOP:
		if _callbacks != null:
			_callbacks.on_simulation_stop()
		if _internal_endpoint != null:
			_internal_endpoint.stop_endpoint()
		var stop_result: int = _core_asset.stop_feedback_ok()
		_update_error("tick.stop_feedback_ok")
		if stop_result == 0:
			simulation_stopped.emit()
		return false

	if event == EVENT_RESET:
		if _callbacks != null:
			_callbacks.on_simulation_reset()
		var reset_result: int = _core_asset.reset_feedback_ok()
		_update_error("tick.reset_feedback_ok")
		if reset_result == 0:
			_current_simtime_usec = 0
			simulation_reset.emit()
		return false

	if event == EVENT_ERROR:
		_last_error_text = "tick failed: received EVENT_ERROR"
		return false

	var state: int = _core_asset.get_simulation_state()
	_update_error("tick.get_simulation_state")
	if state != STATE_RUNNING:
		return false

	var pdu_created: bool = _core_asset.is_pdu_created()
	_update_error("tick.is_pdu_created")
	if not _last_error_text.is_empty():
		return false
	if not pdu_created:
		return false

	var pdu_sync_mode: bool = _core_asset.is_pdu_sync_mode()
	_update_error("tick.is_pdu_sync_mode")
	if not _last_error_text.is_empty():
		return false
	if pdu_sync_mode:
		if _internal_endpoint != null and _internal_endpoint.is_running():
			_internal_endpoint.dispatch_recv_events()
		_core_asset.notify_write_pdu_done()
		_update_error("tick.notify_write_pdu_done")
		return _last_error_text.is_empty() and false

	if _internal_endpoint != null and _internal_endpoint.is_running():
		_internal_endpoint.dispatch_recv_events()

	_core_asset.notify_simtime(_current_simtime_usec)
	_update_error("tick.notify_simtime")
	if not _last_error_text.is_empty():
		return false

	var world_time_usec: int = _core_asset.get_world_time_usec()
	_update_error("tick.get_world_time_usec")
	if not _last_error_text.is_empty():
		return false

	var next_simtime_usec := _current_simtime_usec + delta_time_usec
	if next_simtime_usec > world_time_usec:
		return false

	_current_simtime_usec = next_simtime_usec
	return true

func get_state() -> int:
	if not _ensure_core_asset():
		return STATE_ERROR
	var state: int = _core_asset.get_simulation_state()
	_update_error("get_state")
	return state

func get_world_time_usec() -> int:
	if not _ensure_core_asset():
		return 0
	var world_time_usec: int = _core_asset.get_world_time_usec()
	_update_error("get_world_time_usec")
	return world_time_usec

func get_simtime_usec() -> int:
	return _current_simtime_usec

func get_last_error_text() -> String:
	return _last_error_text

func get_typed_endpoint(_robot: String, _pdu_name: String) -> Variant:
	if not use_internal_shm_endpoint:
		_last_error_text = "get_typed_endpoint failed: internal SHM endpoint is disabled"
		return null
	if not _ensure_internal_endpoint():
		return null
	var typed_endpoint = _internal_endpoint.get_typed_endpoint(_robot, _pdu_name)
	_last_error_text = _internal_endpoint.get_last_error_text()
	return typed_endpoint

func get_endpoint() -> Variant:
	if not use_internal_shm_endpoint:
		_last_error_text = "get_endpoint failed: internal SHM endpoint is disabled"
		return null
	if not _ensure_internal_endpoint():
		return null
	_last_error_text = ""
	return _internal_endpoint

func _ensure_core_asset() -> bool:
	if _core_asset != null:
		return true
	if not ClassDB.class_exists("HakoniwaCoreAsset"):
		_last_error_text = "HakoniwaCoreAsset is not registered"
		return false
	_core_asset = ClassDB.instantiate("HakoniwaCoreAsset") as Node
	if _core_asset == null:
		_last_error_text = "HakoniwaCoreAsset could not be instantiated"
		return false
	add_child(_core_asset)
	return true

func _ensure_internal_endpoint() -> bool:
	if _internal_endpoint != null:
		return true
	_internal_endpoint = HakoniwaEndpointNode.new()
	if _internal_endpoint == null:
		_last_error_text = "HakoniwaEndpointNode could not be instantiated"
		return false
	add_child(_internal_endpoint)
	_internal_endpoint.config_path = shm_endpoint_config_path
	_internal_endpoint.endpoint_name = "%s_shm_endpoint" % asset_name
	_internal_endpoint.direction = 2
	_internal_endpoint.codec_plugins = PackedStringArray([
		"res://addons/hakoniwa/codecs/geometry_msgs_codec"
	])
	return true

func _update_error(context: String) -> void:
	if _core_asset == null:
		return
	var err: String = _core_asset.get_last_error_text()
	if err.is_empty():
		_last_error_text = ""
	else:
		_last_error_text = "%s failed: %s" % [context, err]
