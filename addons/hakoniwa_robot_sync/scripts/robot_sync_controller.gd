class_name HakoniwaRobotSyncController
extends Node

const RobotProfileLoader = preload("res://addons/hakoniwa_robot_sync/scripts/robot_profile_loader.gd")
const RobotProfileValidator = preload("res://addons/hakoniwa_robot_sync/scripts/robot_profile_validator.gd")
const TransformConverter = preload("res://addons/hakoniwa_robot_sync/scripts/transform_converter.gd")
const JointStateMapper = preload("res://addons/hakoniwa_robot_sync/scripts/joint_state_mapper.gd")

@export var sim_node_path: NodePath
@export_file("*.json") var profile_path: String = ""
@export var target_root_path: NodePath
@export var auto_start_on_ready: bool = true
@export var debug_logs: bool = false
@export var apply_base_pose: bool = true
@export var apply_joint_states: bool = true

var _enabled: bool = true
var _ready_ok: bool = false
var _last_error_text: String = ""
var _profile: Dictionary = {}

var _sim: HakoniwaSimNode = null
var _target_root: Node3D = null
var _endpoint = null
var _base_link_endpoint = null
var _joint_states_endpoint = null

var _target_root_initial: Transform3D
var _initial_basis_by_path: Dictionary = {}

func _ready() -> void:
	if not auto_start_on_ready:
		return
	call_deferred("_prepare_on_ready")

func set_enabled(value: bool) -> void:
	_enabled = value

func is_ready() -> bool:
	return _ready_ok

func get_last_error_text() -> String:
	return _last_error_text

func _prepare_on_ready() -> void:
	if not _load_profile():
		push_error(_last_error_text)
		return
	if not _resolve_nodes():
		push_error(_last_error_text)
		return
	_connect_sim_signals()
	_ready_ok = true
	_log("ready")

func _load_profile() -> bool:
	_profile = RobotProfileLoader.load_profile(profile_path)
	_last_error_text = RobotProfileValidator.validate(_profile)
	return _last_error_text.is_empty()

func _resolve_nodes() -> bool:
	var sim_node: Node = get_node_or_null(sim_node_path)
	if sim_node == null or not (sim_node is HakoniwaSimNode):
		_last_error_text = "sim_node_path did not resolve to HakoniwaSimNode"
		return false
	_sim = sim_node

	var root_node: Node = get_node_or_null(target_root_path)
	if root_node == null or not (root_node is Node3D):
		_last_error_text = "target_root_path did not resolve to Node3D"
		return false
	_target_root = root_node
	_target_root_initial = _target_root.transform

	var base_node_path := str(_profile.get("base_node_path", ""))
	if _target_root.get_node_or_null(NodePath(base_node_path)) == null:
		_last_error_text = "base_node_path '%s' was not found under target_root_path" % base_node_path
		return false

	_initial_basis_by_path.clear()
	for mapping in _profile.get("joint_mappings", []):
		var node_path := str(mapping.get("node_path", ""))
		var target: Node = _target_root.get_node_or_null(NodePath(node_path))
		if target == null or not (target is Node3D):
			_last_error_text = "joint mapping node_path '%s' was not found under target_root_path" % node_path
			return false
		_initial_basis_by_path[node_path] = (target as Node3D).transform.basis

	return true

func _connect_sim_signals() -> void:
	if not _sim.simulation_ready.is_connected(_on_simulation_ready):
		_sim.simulation_ready.connect(_on_simulation_ready)
	if not _sim.simulation_started.is_connected(_on_simulation_started):
		_sim.simulation_started.connect(_on_simulation_started)
	if not _sim.simulation_stopped.is_connected(_on_simulation_stopped):
		_sim.simulation_stopped.connect(_on_simulation_stopped)
	if not _sim.simulation_reset.is_connected(_on_simulation_reset):
		_sim.simulation_reset.connect(_on_simulation_reset)
	if not _sim.simulation_step.is_connected(_on_simulation_step):
		_sim.simulation_step.connect(_on_simulation_step)

func _on_simulation_ready() -> void:
	if not _enabled:
		return
	_endpoint = _sim.get_endpoint()
	if _endpoint == null:
		_last_error_text = _sim.get_last_error_text()
		push_error(_last_error_text)
		return

	var robot_name := str(_profile.get("robot_name", ""))
	var base_pdu_name := str(_profile.get("base_link_pdu_name", ""))
	var joints_pdu_name := str(_profile.get("joint_states_pdu_name", ""))

	var base_ret: int = _endpoint.create_pdu_lchannel(robot_name, base_pdu_name)
	var joints_ret: int = _endpoint.create_pdu_lchannel(robot_name, joints_pdu_name)
	if base_ret != 0 or joints_ret != 0:
		_last_error_text = _endpoint.get_last_error_text()
		push_error(_last_error_text)
		return

	_base_link_endpoint = _sim.get_typed_endpoint(robot_name, base_pdu_name)
	_joint_states_endpoint = _sim.get_typed_endpoint(robot_name, joints_pdu_name)
	if _base_link_endpoint == null or _joint_states_endpoint == null:
		_last_error_text = _sim.get_last_error_text()
		push_error(_last_error_text)
		return

	_log("simulation_ready bound endpoints")

func _on_simulation_started() -> void:
	_log("simulation_started")

func _on_simulation_stopped() -> void:
	_log("simulation_stopped")

func _on_simulation_reset() -> void:
	if _target_root != null:
		_target_root.transform = _target_root_initial
	for node_path in _initial_basis_by_path.keys():
		var target: Node = _target_root.get_node_or_null(NodePath(node_path))
		if target != null and target is Node3D:
			(target as Node3D).transform.basis = _initial_basis_by_path[node_path]
	_log("simulation_reset")

func _on_simulation_step(_simtime_usec: int, _world_time_usec: int) -> void:
	if not _enabled or _endpoint == null:
		return
	if _base_link_endpoint == null or _joint_states_endpoint == null:
		return

	_endpoint.process_recv_events()

	if apply_base_pose:
		var base_link_pos: Dictionary = _base_link_endpoint.recv_dict()
		if not base_link_pos.is_empty():
			TransformConverter.apply_base_pose(
				_target_root,
				_target_root_initial,
				base_link_pos,
				_profile.get("coordinate_system", {})
			)

	if apply_joint_states:
		var joint_states: Dictionary = _joint_states_endpoint.recv_dict()
		if not joint_states.is_empty():
			JointStateMapper.apply_joint_states(
				_target_root,
				_profile,
				_initial_basis_by_path,
				joint_states
			)

func _log(message: String) -> void:
	if debug_logs:
		print("HakoniwaRobotSyncController: ", message)
