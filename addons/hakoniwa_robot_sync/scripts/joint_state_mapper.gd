class_name HakoniwaJointStateMapper
extends RefCounted

static func apply_joint_states(target_root: Node, profile: Dictionary, initial_basis_by_path: Dictionary, pdu: Dictionary) -> void:
	var lookup := _build_position_lookup(pdu)
	if lookup.is_empty():
		return

	var joint_mappings: Array = profile.get("joint_mappings", [])
	for mapping in joint_mappings:
		var joint_name := str(mapping.get("joint_name", ""))
		if not lookup.has(joint_name):
			continue
		var node_path := str(mapping.get("node_path", ""))
		var target: Node = target_root.get_node_or_null(NodePath(node_path))
		if target == null or not (target is Node3D):
			continue

		var initial_basis: Variant = initial_basis_by_path.get(node_path, null)
		if initial_basis == null or typeof(initial_basis) != TYPE_BASIS:
			continue

		var node: Node3D = target
		var axis_name := str(mapping.get("axis", "z"))
		var axis := _axis_from_name(axis_name)
		var sign := float(mapping.get("sign", 1.0))
		var offset_rad := float(mapping.get("offset_rad", 0.0))
		var angle := sign * float(lookup[joint_name]) + offset_rad
		node.transform.basis = initial_basis * Basis(axis, angle)

static func _build_position_lookup(pdu: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var names: Array = pdu.get("name", [])
	var positions: Array = pdu.get("position", [])
	for index in range(names.size()):
		if index >= positions.size():
			continue
		result[str(names[index])] = float(positions[index])
	return result

static func _axis_from_name(axis_name: String) -> Vector3:
	match axis_name:
		"x":
			return Vector3(1, 0, 0)
		"y":
			return Vector3(0, 1, 0)
		_:
			return Vector3(0, 0, 1)
