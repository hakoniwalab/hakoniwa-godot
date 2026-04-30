class_name HakoniwaRobotProfileValidator
extends RefCounted

static func validate(profile: Dictionary) -> String:
	if profile.is_empty():
		return "profile is empty"
	if typeof(profile.get("version", null)) not in [TYPE_INT, TYPE_FLOAT]:
		return "profile.version must be numeric"
	if not _is_non_empty_string(profile.get("robot_name", "")):
		return "profile.robot_name must be non-empty"
	if not _is_non_empty_string(profile.get("base_link_pdu_name", "")):
		return "profile.base_link_pdu_name must be non-empty"
	if not _is_non_empty_string(profile.get("joint_states_pdu_name", "")):
		return "profile.joint_states_pdu_name must be non-empty"
	if not _is_non_empty_string(profile.get("base_node_path", "")):
		return "profile.base_node_path must be non-empty"

	var coordinate_system: Variant = profile.get("coordinate_system", {})
	if typeof(coordinate_system) != TYPE_DICTIONARY:
		return "profile.coordinate_system must be Dictionary"
	if not _is_non_empty_string(coordinate_system.get("position_rule", "")):
		return "profile.coordinate_system.position_rule must be non-empty"
	if not _is_non_empty_string(coordinate_system.get("rotation_rule", "")):
		return "profile.coordinate_system.rotation_rule must be non-empty"

	var joint_mappings: Variant = profile.get("joint_mappings", [])
	if typeof(joint_mappings) != TYPE_ARRAY:
		return "profile.joint_mappings must be Array"
	for index in range(joint_mappings.size()):
		var mapping: Variant = joint_mappings[index]
		if typeof(mapping) != TYPE_DICTIONARY:
			return "profile.joint_mappings[%d] must be Dictionary" % index
		if not _is_non_empty_string(mapping.get("joint_name", "")):
			return "profile.joint_mappings[%d].joint_name must be non-empty" % index
		if not _is_non_empty_string(mapping.get("node_path", "")):
			return "profile.joint_mappings[%d].node_path must be non-empty" % index
		var axis := str(mapping.get("axis", ""))
		if axis != "x" and axis != "y" and axis != "z":
			return "profile.joint_mappings[%d].axis must be x, y, or z" % index
		if typeof(mapping.get("sign", null)) not in [TYPE_INT, TYPE_FLOAT]:
			return "profile.joint_mappings[%d].sign must be numeric" % index
		if typeof(mapping.get("offset_rad", null)) not in [TYPE_INT, TYPE_FLOAT]:
			return "profile.joint_mappings[%d].offset_rad must be numeric" % index
		if not _is_non_empty_string(mapping.get("apply_mode", "")):
			return "profile.joint_mappings[%d].apply_mode must be non-empty" % index

	return ""

static func _is_non_empty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not String(value).strip_edges().is_empty()
