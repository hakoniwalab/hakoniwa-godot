extends Node

var _sim = null
var _requested_first_stop := false
var _restart_pending := false
var _completed := false
var _pending_reset_request := false
var _pending_restart_request := false
var _post_restart_step_count := 0
const POST_RESTART_STEP_TARGET := 3


func _ready() -> void:
	print("HAKO_CORE_SMOKE_BOOT")

	var extension: Resource = load("res://addons/hakoniwa/hakoniwa.gdextension")
	if extension == null:
		print("HAKO_CORE_SMOKE_PENDING_EXTENSION_LOAD_FAILED")
		get_tree().quit(2)
		return

	var sim_node_script_path := _get_repo_file_path("addons/hakoniwa/scripts/hakoniwa_simulation_node.gd")
	var callbacks_script_path := _get_repo_file_path("examples/core_pro_smoke/smoke_callbacks.gd")

	if not FileAccess.file_exists(sim_node_script_path):
		print("HAKO_CORE_SMOKE_PENDING_MISSING_SIMNODE")
		get_tree().quit(2)
		return

	var sim_script := load(sim_node_script_path)
	if sim_script == null:
		print("HAKO_CORE_SMOKE_PENDING_LOAD_FAILED")
		get_tree().quit(2)
		return

	var callbacks_script := load(callbacks_script_path)
	if callbacks_script == null:
		print("HAKO_CORE_SMOKE_PENDING_LOAD_FAILED_CALLBACKS")
		get_tree().quit(2)
		return

	_sim = sim_script.new()
	add_child(_sim)

	var required_methods := [
		"set_callbacks",
		"initialize",
		"request_start",
		"request_stop",
		"request_reset",
		"get_state",
		"get_simtime_usec",
	]

	for method_name in required_methods:
		if not _sim.has_method(method_name):
			print("HAKO_CORE_SMOKE_PENDING_MISSING_METHOD:%s" % method_name)
			get_tree().quit(2)
			return

	_sim.asset_name = "godot_core_pro_smoke"
	_sim.delta_time_usec = 20000
	_sim.enable_physics_time_sync = false
	_sim.simulation_started.connect(_on_simulation_started)
	_sim.simulation_stopped.connect(_on_simulation_stopped)
	_sim.simulation_reset.connect(_on_simulation_reset)
	_sim.simulation_step.connect(_on_simulation_step)
	_sim.set_callbacks(callbacks_script.new())

	var initialize_result: int = _sim.initialize()
	if initialize_result != 0:
		print("HAKO_CORE_SMOKE_INITIALIZE_FAILED")
		print(_sim.get_last_error_text())
		get_tree().quit(2)
		return

	print("HAKO_CORE_SMOKE_SCENE_READY")
	print("HAKO_CORE_SMOKE_INITIALIZED")
	print("HAKO_CORE_SMOKE_REGISTERED")

	var start_result: int = _sim.request_start()
	if start_result != 0:
		print("HAKO_CORE_SMOKE_REQUEST_START_FAILED")
		print(_sim.get_last_error_text())
		get_tree().quit(2)

func _physics_process(_delta: float) -> void:
	if _sim == null or _completed:
		return

	if _pending_reset_request:
		if _sim.get_state() == _sim.STATE_STOPPED:
			_pending_reset_request = false
			var reset_result: int = _sim.request_reset()
			if reset_result != 0:
				print("HAKO_CORE_SMOKE_REQUEST_RESET_FAILED")
				print(_sim.get_last_error_text())
				get_tree().quit(2)
				return

	if _pending_restart_request:
		if _sim.get_state() == _sim.STATE_STOPPED:
			_pending_restart_request = false
			_restart_pending = true
			var restart_result: int = _sim.request_start()
			if restart_result != 0:
				print("HAKO_CORE_SMOKE_REQUEST_RESTART_FAILED")
				print(_sim.get_last_error_text())
				get_tree().quit(2)
				return

func _on_simulation_started() -> void:
	if _restart_pending:
		print("HAKO_CORE_SMOKE_RESTART_FEEDBACK_OK")
	else:
		print("HAKO_CORE_SMOKE_START_FEEDBACK_OK")

func _on_simulation_stopped() -> void:
	print("HAKO_CORE_SMOKE_STOP_FEEDBACK_OK")
	_pending_reset_request = true

func _on_simulation_reset() -> void:
	print("HAKO_CORE_SMOKE_RESET_FEEDBACK_OK")
	_pending_restart_request = true

func _on_simulation_step(_simtime_usec: int, world_time_usec: int) -> void:
	if _sim == null or _completed:
		return
	if _restart_pending:
		_post_restart_step_count += 1
		print("HAKO_CORE_SMOKE_STEP:%d simtime=%d world=%d" % [
			_post_restart_step_count,
			_sim.get_simtime_usec(),
			world_time_usec
		])
		if _post_restart_step_count >= POST_RESTART_STEP_TARGET:
			_completed = true
			print("HAKO_CORE_SMOKE_OK")
			get_tree().quit(0)
		return
	if not _requested_first_stop:
		_requested_first_stop = true
		var stop_result: int = _sim.request_stop()
		if stop_result != 0:
			print("HAKO_CORE_SMOKE_REQUEST_STOP_FAILED")
			print(_sim.get_last_error_text())
			get_tree().quit(2)

func _get_repo_file_path(relative_path: String) -> String:
	var example_root := ProjectSettings.globalize_path("res://")
	return example_root.path_join("..").path_join("..").path_join(relative_path).simplify_path()
