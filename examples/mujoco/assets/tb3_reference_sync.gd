extends Node

@onready var sim: HakoniwaSimNode = $"../HakoniwaSimNode"

@onready var ros_to_godot: Node3D = $"../RosToGodot"
@onready var wheel_left: Node3D = $"../RosToGodot/Visuals/base_link/wheel_left_link"
@onready var wheel_right: Node3D = $"../RosToGodot/Visuals/base_link/wheel_right_link"

var _endpoint = null
var _base_link_endpoint = null
var _joint_states_endpoint = null

var ros_to_godot_initial: Transform3D
var left_initial_basis: Basis
var right_initial_basis: Basis

var _debug_count := 0


func _ready() -> void:
	sim.simulation_ready.connect(_on_simulation_ready)
	sim.simulation_started.connect(_on_simulation_started)
	sim.simulation_stopped.connect(_on_simulation_stopped)
	sim.simulation_reset.connect(_on_simulation_reset)
	sim.simulation_step.connect(_on_simulation_step)

	# RosToGodot は ROS/URDF 座標系を Godot 座標系へ写す固定変換。
	# 現状はここに base_link の絶対姿勢も合成して使う。
	ros_to_godot_initial = ros_to_godot.transform

	# wheel link の初期姿勢。
	# URDF joint origin の rpy="-1.57 0 0" などを含む。
	left_initial_basis = wheel_left.transform.basis
	right_initial_basis = wheel_right.transform.basis


func _on_simulation_ready() -> void:
	_endpoint = sim.get_endpoint()
	if _endpoint == null:
		push_error(sim.get_last_error_text())
		return

	var base_link_ret = _endpoint.create_pdu_lchannel("TB3", "base_link_pos")
	var joint_states_ret = _endpoint.create_pdu_lchannel("TB3", "joint_states")

	print("INFO: create base_link_pos pdu channel: ret = ", base_link_ret)
	print("INFO: create joint_states pdu channel: ret = ", joint_states_ret)

	if base_link_ret != 0 or joint_states_ret != 0:
		push_error(_endpoint.get_last_error_text())
		return

	_base_link_endpoint = sim.get_typed_endpoint("TB3", "base_link_pos")
	_joint_states_endpoint = sim.get_typed_endpoint("TB3", "joint_states")

	if _base_link_endpoint == null or _joint_states_endpoint == null:
		print("sample endpoint bind failed")
		print(sim.get_last_error_text())
		return


func _process(delta: float) -> void:
	# PDU同期で動かすので、ここでは何もしない。
	pass


func _on_simulation_started() -> void:
	print("simulation started")


func _on_simulation_stopped() -> void:
	print("simulation stopped")


func _on_simulation_reset() -> void:
	print("simulation reset")

	# 表示状態を初期状態へ戻す。
	ros_to_godot.transform = ros_to_godot_initial
	wheel_left.transform.basis = left_initial_basis
	wheel_right.transform.basis = right_initial_basis


func _on_simulation_step(simtime_usec: int, world_time_usec: int) -> void:
	if _endpoint == null:
		return
	if _base_link_endpoint == null:
		return
	if _joint_states_endpoint == null:
		return

	_endpoint.process_recv_events()

	var base_link_pos: Dictionary = _base_link_endpoint.recv_dict()
	if not base_link_pos.is_empty():
		_apply_base_link_pos(base_link_pos)

	var joint_states: Dictionary = _joint_states_endpoint.recv_dict()
	if not joint_states.is_empty():
		_apply_joint_states(joint_states)

	_debug_count += 1
	if _debug_count % 100 == 0:
		print("step simtime=%d world=%d pending=%d" % [
			simtime_usec,
			world_time_usec,
			_endpoint.get_pending_count()
		])


func _apply_base_link_pos(pdu: Dictionary) -> void:
	var linear: Dictionary = pdu.get("linear", {})
	var angular: Dictionary = pdu.get("angular", {})

	# MuJoCo/ROS系:
	#   X forward
	#   Y left
	#   Z up
	var ros_x := float(linear.get("x", 0.0))
	var ros_y := float(linear.get("y", 0.0))
	var ros_z := float(linear.get("z", 0.0))

	var roll := float(angular.get("x", 0.0))
	var pitch := float(angular.get("y", 0.0))
	var yaw := float(angular.get("z", 0.0))

	# Godot:
	#   X right
	#   Y up
	#   -Z forward
	var godot_pos := _ros_position_to_godot(Vector3(ros_x, ros_y, ros_z))

	# ROS座標系の姿勢を Godot座標系の姿勢へ変換する。
	var ros_basis := _basis_from_ros_rpy(roll, pitch, yaw)
	var godot_basis := _ros_basis_to_godot(ros_basis)

	# 現状は RosToGodot ノードに、
	#   body pose in Godot * fixed RosToGodot transform
	# を入れる。
	#
	# つまり:
	#   ros_to_godot.transform = T_body_godot * C_ros_to_godot
	#
	# これにより、RosToGodot 以下の URDF ローカル構造は維持しつつ、
	# ロボット全体を Godot 世界で動かす。
	var body_transform := Transform3D(godot_basis, godot_pos)
	ros_to_godot.transform = body_transform * ros_to_godot_initial


func _apply_joint_states(pdu: Dictionary) -> void:
	var names: Array = pdu.get("name", [])
	var positions: Array = pdu.get("position", [])

	for i in range(names.size()):
		if i >= positions.size():
			continue

		var joint_name := str(names[i])
		var angle := float(positions[i])

		match joint_name:
			"wheel_left_joint":
				# URDF joint axis: xyz="0 0 1"
				# qpos は絶対角[rad]なので、初期姿勢から毎回作り直す。
				wheel_left.transform.basis = left_initial_basis * Basis(Vector3(0, 0, 1), angle)

			"wheel_right_joint":
				# URDF joint axis: xyz="0 0 1"
				wheel_right.transform.basis = right_initial_basis * Basis(Vector3(0, 0, 1), angle)


func _ros_position_to_godot(ros_pos: Vector3) -> Vector3:
	# ROS:
	#   x = forward
	#   y = left
	#   z = up
	#
	# Godot:
	#   x = right
	#   y = up
	#   z = backward
	#
	# Mapping:
	#   godot_x = -ros_y
	#   godot_y =  ros_z
	#   godot_z = -ros_x
	return Vector3(
		-ros_pos.y,
		ros_pos.z,
		-ros_pos.x
	)


func _basis_from_ros_rpy(roll: float, pitch: float, yaw: float) -> Basis:
	# ROS/URDF系の roll-pitch-yaw。
	# 一般的な合成:
	#   R = Rz(yaw) * Ry(pitch) * Rx(roll)
	var rx := Basis(Vector3(1, 0, 0), roll)
	var ry := Basis(Vector3(0, 1, 0), pitch)
	var rz := Basis(Vector3(0, 0, 1), yaw)
	return rz * ry * rx


func _ros_basis_to_godot(ros_basis: Basis) -> Basis:
	# ros_to_godot_initial.basis が C。
	# C は ROS座標系を Godot座標系へ写す固定変換。
	#
	# 姿勢の変換は:
	#   R_godot = C * R_ros * C^-1
	var c := ros_to_godot_initial.basis
	return c * ros_basis * c.inverse()
