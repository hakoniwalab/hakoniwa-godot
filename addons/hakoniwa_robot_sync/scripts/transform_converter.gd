class_name HakoniwaTransformConverter
extends RefCounted

static func ros_position_to_godot(ros_pos: Vector3) -> Vector3:
	return Vector3(
		-ros_pos.y,
		ros_pos.z,
		-ros_pos.x
	)

static func basis_from_rpy(roll: float, pitch: float, yaw: float) -> Basis:
	# Current Hakoniwa/MuJoCo TB3 pose output behaves with inverted pitch
	# relative to the viewer expectation, so compensate before basis synthesis.
	pitch = -pitch
	var rx := Basis(Vector3(1, 0, 0), roll)
	var ry := Basis(Vector3(0, 1, 0), pitch)
	var rz := Basis(Vector3(0, 0, 1), yaw)
	return rz * ry * rx

static func convert_position(rule_name: String, ros_pos: Vector3) -> Vector3:
	match rule_name:
		"identity":
			return ros_pos
		"hakoniwa_to_godot", "ros_to_godot":
			return ros_position_to_godot(ros_pos)
		_:
			return ros_pos

static func convert_basis(rule_name: String, ros_basis: Basis, conversion_basis: Basis) -> Basis:
	match rule_name:
		"identity":
			return ros_basis
		"hakoniwa_to_godot", "ros_to_godot":
			return conversion_basis * ros_basis * conversion_basis.inverse()
		_:
			return ros_basis

static func apply_base_pose(target_root: Node3D, initial_transform: Transform3D, pdu: Dictionary, coordinate_system: Dictionary) -> void:
	var linear: Dictionary = pdu.get("linear", {})
	var angular: Dictionary = pdu.get("angular", {})

	var ros_pos := Vector3(
		float(linear.get("x", 0.0)),
		float(linear.get("y", 0.0)),
		float(linear.get("z", 0.0))
	)
	var roll := float(angular.get("x", 0.0))
	var pitch := float(angular.get("y", 0.0))
	var yaw := float(angular.get("z", 0.0))

	var pos_rule := str(coordinate_system.get("position_rule", "hakoniwa_to_godot"))
	var rot_rule := str(coordinate_system.get("rotation_rule", "hakoniwa_to_godot"))

	var godot_pos := convert_position(pos_rule, ros_pos)
	var ros_basis := basis_from_rpy(roll, pitch, yaw)
	var godot_basis := convert_basis(rot_rule, ros_basis, initial_transform.basis)
	var body_transform := Transform3D(godot_basis, godot_pos)
	target_root.transform = body_transform * initial_transform
