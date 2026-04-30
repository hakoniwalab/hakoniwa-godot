class_name HakoniwaRobotProfileLoader
extends RefCounted

static func load_profile(path: String) -> Dictionary:
	if path.strip_edges().is_empty():
		return {}
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var text := file.get_as_text()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data
