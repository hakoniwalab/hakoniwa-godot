class_name HakoniwaSimNode
extends Node

signal simulation_started
signal simulation_stopped
signal simulation_reset
signal simulation_step(simtime_usec, world_time_usec)
signal simulation_ready

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

const SYNC_STATE_UNINITIALIZED := 0
const SYNC_STATE_STOPPED := 1
const SYNC_STATE_RUNNING := 2
const SYNC_STATE_BLOCKED_BY_WORLD_TIME := 3
const SYNC_STATE_RESETTING := 4
const SYNC_STATE_ERROR := 5
const SYNC_STATE_TERMINATED := 6

@export var asset_name: String = ""
@export var use_internal_shm_endpoint: bool = false
@export var shm_endpoint_config_path: String = ""
@export var internal_endpoint_codec_packages: PackedStringArray = PackedStringArray([
	"geometry_msgs"
])
@export var delta_time_usec: int = 20000
@export var auto_sync_delta_time_with_physics: bool = true
@export var auto_initialize_on_ready: bool = false
@export var auto_unregister_on_exit: bool = true
@export var auto_tick_on_physics_process: bool = false
@export var enable_physics_time_sync: bool = false
@export var debug_time_sync_logs: bool = false

var _core_asset: Node = null
var _internal_endpoint: Node = null
var _callbacks = null
var _last_error_text: String = ""
var _current_simtime_usec: int = 0
var _sync_state: int = SYNC_STATE_UNINITIALIZED
var _blocked_tree_pause_applied: bool = false
var _last_blocked_next_simtime_usec: int = -1
var _last_blocked_world_time_usec: int = -1
var internal_endpoint_codec_plugins: PackedStringArray = PackedStringArray()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if auto_initialize_on_ready:
		var result := initialize()
		if result != 0:
			push_error(_last_error_text)

func _process(_delta: float) -> void:
	if _sync_state == SYNC_STATE_UNINITIALIZED or _sync_state == SYNC_STATE_TERMINATED:
		return
	if enable_physics_time_sync and _sync_state == SYNC_STATE_BLOCKED_BY_WORLD_TIME:
		var step_ready := _tick_internal(false)
		if step_ready:
			_leave_blocked_state()

func _physics_process(_delta: float) -> void:
	if _sync_state == SYNC_STATE_UNINITIALIZED or _sync_state == SYNC_STATE_TERMINATED:
		return
	if enable_physics_time_sync and _sync_state == SYNC_STATE_BLOCKED_BY_WORLD_TIME:
		return
	_tick_internal(true)

func _exit_tree() -> void:
	_leave_blocked_state()
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
	if enable_physics_time_sync and auto_sync_delta_time_with_physics:
		var synced_delta_time_usec := _get_physics_delta_time_usec()
		if synced_delta_time_usec <= 0:
			_last_error_text = "initialize failed: physics_ticks_per_second must be > 0"
			return -1
		delta_time_usec = synced_delta_time_usec
		_debug_log("auto-sync delta_time_usec=%d physics_ticks_per_second=%d" % [
			delta_time_usec,
			Engine.physics_ticks_per_second
		])
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
		print("internal SHM endpoint initialized with config: %s" % shm_endpoint_config_path)
	var result: int = _core_asset.initialize_asset(asset_name)
	_update_error("initialize")
	if result == 0:
		_current_simtime_usec = 0
		_sync_state = SYNC_STATE_STOPPED
		call_deferred("_emit_initialized")
	return result

func shutdown() -> void:
	_leave_blocked_state()
	if _core_asset == null:
		return
	if _internal_endpoint != null:
		_internal_endpoint.stop_endpoint()
		_internal_endpoint.close_endpoint()
	_core_asset.unregister_asset()
	_update_error("shutdown")
	if _last_error_text.is_empty():
		_current_simtime_usec = 0
		_sync_state = SYNC_STATE_TERMINATED
	else:
		_sync_state = SYNC_STATE_ERROR

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

func get_state() -> int:
	if not _ensure_core_asset():
		return STATE_ERROR
	var state: int = _core_asset.get_simulation_state()
	_update_error("get_state")
	return state

func get_sync_state() -> int:
	return _sync_state

func is_blocked_by_world_time() -> bool:
	return _sync_state == SYNC_STATE_BLOCKED_BY_WORLD_TIME

func get_world_time_usec() -> int:
	if not _ensure_core_asset():
		return 0
	var world_time_usec: int = _core_asset.get_world_time_usec()
	_update_error("get_world_time_usec")
	return world_time_usec

func get_configured_delta_time_usec() -> int:
	return delta_time_usec

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

func _emit_initialized() -> void:
	simulation_ready.emit()

func _tick_internal(allow_step: bool) -> bool:
	if not _ensure_core_asset():
		_sync_state = SYNC_STATE_ERROR
		return false

	var event: int = _core_asset.poll_event()
	_update_error("tick.poll_event")
	if event < 0:
		_sync_state = SYNC_STATE_ERROR
		return false

	if event == EVENT_START:
		return _handle_start_event()

	if event == EVENT_STOP:
		_handle_stop_event()
		return false

	if event == EVENT_RESET:
		_handle_reset_event()
		return false

	if event == EVENT_ERROR:
		_last_error_text = "tick failed: received EVENT_ERROR"
		_sync_state = SYNC_STATE_ERROR
		return false

	var state: int = _core_asset.get_simulation_state()
	_update_error("tick.get_simulation_state")
	if not _last_error_text.is_empty():
		_sync_state = SYNC_STATE_ERROR
		return false
	if state != STATE_RUNNING:
		_sync_state = SYNC_STATE_STOPPED
		return false
	_sync_state = SYNC_STATE_RUNNING

	var pdu_created: bool = _core_asset.is_pdu_created()
	_update_error("tick.is_pdu_created")
	if not _last_error_text.is_empty():
		_sync_state = SYNC_STATE_ERROR
		return false
	if not pdu_created:
		return false

	var pdu_sync_mode: bool = _core_asset.is_pdu_sync_mode()
	_update_error("tick.is_pdu_sync_mode")
	if not _last_error_text.is_empty():
		_sync_state = SYNC_STATE_ERROR
		return false
	if pdu_sync_mode:
		if _internal_endpoint != null and _internal_endpoint.is_running():
			_internal_endpoint.dispatch_recv_events()
		_core_asset.notify_write_pdu_done()
		_update_error("tick.notify_write_pdu_done")
		if not _last_error_text.is_empty():
			_sync_state = SYNC_STATE_ERROR
		return false

	var world_time_usec: int = _core_asset.get_world_time_usec()
	_update_error("tick.get_world_time_usec")
	if not _last_error_text.is_empty():
		_sync_state = SYNC_STATE_ERROR
		return false

	var next_simtime_usec := _current_simtime_usec + delta_time_usec
	var step_ready := next_simtime_usec <= world_time_usec
	if not step_ready:
		if _last_blocked_next_simtime_usec != next_simtime_usec or _last_blocked_world_time_usec != world_time_usec:
			_last_blocked_next_simtime_usec = next_simtime_usec
			_last_blocked_world_time_usec = world_time_usec
			_debug_log("step blocked: next_simtime=%d world_time=%d" % [
				next_simtime_usec,
				world_time_usec
			])
		if enable_physics_time_sync and allow_step:
			_enter_blocked_state()
		return false

	if not allow_step:
		_debug_log("step ready while blocked monitor: next_simtime=%d world_time=%d" % [
			next_simtime_usec,
			world_time_usec
		])
		return true

	_leave_blocked_state()
	if _internal_endpoint != null and _internal_endpoint.is_running():
		_internal_endpoint.dispatch_recv_events()

	_current_simtime_usec = next_simtime_usec
	_debug_log("notify_simtime simtime=%d world_time=%d" % [
		_current_simtime_usec,
		world_time_usec
	])
	_core_asset.notify_simtime(_current_simtime_usec)
	_update_error("tick.notify_simtime")
	if not _last_error_text.is_empty():
		_sync_state = SYNC_STATE_ERROR
		return false

	if _callbacks != null and _callbacks.has_method("on_simulation_step"):
		_callbacks.on_simulation_step(_current_simtime_usec, world_time_usec)
	_debug_log("emit simulation_step simtime=%d world_time=%d" % [
		_current_simtime_usec,
		world_time_usec
	])
	simulation_step.emit(_current_simtime_usec, world_time_usec)
	_debug_log("simulation_step simtime=%d world_time=%d" % [
		_current_simtime_usec,
		world_time_usec
	])
	return true

func _handle_start_event() -> bool:
	_leave_blocked_state()
	var pdu_created: bool = _core_asset.is_pdu_created()
	_update_error("tick.is_pdu_created")	
	if _internal_endpoint != null:
		var start_endpoint_result: int = _internal_endpoint.start_endpoint()
		if start_endpoint_result != 0:
			_last_error_text = _internal_endpoint.get_last_error_text()
			_sync_state = SYNC_STATE_ERROR
			print("start_endpoint failed: %s" % _last_error_text)
			return false
		var post_start_endpoint_result: int = _internal_endpoint.post_start_endpoint()
		if post_start_endpoint_result != 0:
			_last_error_text = _internal_endpoint.get_last_error_text()
			_sync_state = SYNC_STATE_ERROR
			print("post_start_endpoint failed: %s" % _last_error_text)
			return false
	if _callbacks != null:
		_callbacks.on_simulation_start()
	_core_asset.notify_write_pdu_done()
	_update_error("tick.notify_write_pdu_done")
	if not _last_error_text.is_empty():
		_sync_state = SYNC_STATE_ERROR
		return false
	var start_result: int = _core_asset.start_feedback_ok()
	_update_error("tick.start_feedback_ok")
	if start_result == 0:
		_sync_state = SYNC_STATE_RUNNING
		simulation_started.emit()
		return true
	_sync_state = SYNC_STATE_ERROR
	return false

func _handle_stop_event() -> void:
	_leave_blocked_state()
	if _callbacks != null:
		_callbacks.on_simulation_stop()
	if _internal_endpoint != null:
		_internal_endpoint.stop_endpoint()
	var stop_result: int = _core_asset.stop_feedback_ok()
	_update_error("tick.stop_feedback_ok")
	if stop_result == 0:
		_sync_state = SYNC_STATE_STOPPED
		simulation_stopped.emit()
	else:
		_sync_state = SYNC_STATE_ERROR

func _handle_reset_event() -> void:
	_leave_blocked_state()
	if _callbacks != null:
		_callbacks.on_simulation_reset()
	var reset_result: int = _core_asset.reset_feedback_ok()
	_update_error("tick.reset_feedback_ok")
	if reset_result == 0:
		_current_simtime_usec = 0
		_debug_log("reset feedback ok: local simtime reset to 0")
		_sync_state = SYNC_STATE_RESETTING
		simulation_reset.emit()
	else:
		_sync_state = SYNC_STATE_ERROR

func _enter_blocked_state() -> void:
	if _sync_state == SYNC_STATE_BLOCKED_BY_WORLD_TIME:
		return
	_sync_state = SYNC_STATE_BLOCKED_BY_WORLD_TIME
	_last_blocked_next_simtime_usec = -1
	_last_blocked_world_time_usec = -1
	_debug_log("SYNC_STATE_BLOCKED_BY_WORLD_TIME")
	_apply_pause_backend(true)

func _leave_blocked_state() -> void:
	if _sync_state == SYNC_STATE_BLOCKED_BY_WORLD_TIME:
		_sync_state = SYNC_STATE_RUNNING
		_debug_log("SYNC_STATE_RUNNING")
	_last_blocked_next_simtime_usec = -1
	_last_blocked_world_time_usec = -1
	_apply_pause_backend(false)

func _apply_pause_backend(blocked: bool) -> void:
	if not enable_physics_time_sync:
		return
	var tree := get_tree()
	if tree == null:
		return
	if blocked:
		if not tree.paused:
			tree.paused = true
			_blocked_tree_pause_applied = true
			_debug_log("PHYSICS_BACKEND_PAUSED")
	else:
		if _blocked_tree_pause_applied and tree.paused:
			tree.paused = false
			_debug_log("PHYSICS_BACKEND_RESUMED")
		_blocked_tree_pause_applied = false

func _get_physics_delta_time_usec() -> int:
	if Engine.physics_ticks_per_second <= 0:
		return 0
	return int(round(1000000.0 / float(Engine.physics_ticks_per_second)))

func _debug_log(message: String) -> void:
	if not debug_time_sync_logs:
		return
	print("HAKO_SIM_DEBUG: %s" % message)

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
	_internal_endpoint.codec_plugins = _resolve_internal_endpoint_codec_plugins()
	return true

func _resolve_internal_endpoint_codec_plugins() -> PackedStringArray:
	var resolved := PackedStringArray()
	for package_name in internal_endpoint_codec_packages:
		var trimmed := package_name.strip_edges()
		if trimmed.is_empty():
			continue
		if trimmed.begins_with("res://"):
			resolved.append(trimmed)
			continue
		resolved.append("res://addons/hakoniwa/codecs/%s_codec" % trimmed)
	for plugin_path in internal_endpoint_codec_plugins:
		var trimmed := plugin_path.strip_edges()
		if trimmed.is_empty():
			continue
		if not resolved.has(trimmed):
			resolved.append(trimmed)
	return resolved

func _update_error(context: String) -> void:
	if _core_asset == null:
		return
	var err: String = _core_asset.get_last_error_text()
	if err.is_empty():
		_last_error_text = ""
	else:
		_last_error_text = "%s failed: %s" % [context, err]
