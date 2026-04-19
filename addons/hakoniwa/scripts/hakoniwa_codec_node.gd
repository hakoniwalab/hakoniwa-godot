class_name HakoniwaCodecNode
extends Node

signal codec_manifest_loaded()
signal codec_manifest_failed(error_message: String)

@export_file("*.json") var codec_manifest_path: String = "res://addons/hakoniwa/codec_manifest.json"
@export var load_on_ready: bool = true
@export var fail_fast: bool = true

var is_ready: bool = false
var last_error: String = ""

var message_script_roots: PackedStringArray = []
var loaded_extensions: PackedStringArray = []
var skipped_extensions: PackedStringArray = []
var _registry: Node = null

func _ready() -> void:
	if load_on_ready:
		initialize()

func initialize() -> bool:
	is_ready = false
	last_error = ""
	loaded_extensions = PackedStringArray()
	skipped_extensions = PackedStringArray()
	message_script_roots = PackedStringArray()

	if not _ensure_registry():
		push_error(last_error)
		return false
		
	if codec_manifest_path.is_empty():
		return _fail("codec_manifest_path is empty")

	if not FileAccess.file_exists(codec_manifest_path):
		return _fail("Codec manifest not found: %s" % codec_manifest_path)

	var text := FileAccess.get_file_as_string(codec_manifest_path)
	if text.is_empty():
		return _fail("Codec manifest is empty: %s" % codec_manifest_path)

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return _fail(
			"Failed to parse codec manifest: %s (line=%d, message=%s)" % [
				codec_manifest_path,
				json.get_error_line(),
				json.get_error_message()
			]
		)

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return _fail("Codec manifest root must be a Dictionary: %s" % codec_manifest_path)

	var manifest: Dictionary = data

	if manifest.has("message_script_roots"):
		var roots = manifest["message_script_roots"]
		if typeof(roots) != TYPE_ARRAY:
			return _fail("message_script_roots must be an Array: %s" % codec_manifest_path)
		for root in roots:
			if typeof(root) != TYPE_STRING:
				return _fail("message_script_roots must contain only String values")
			message_script_roots.append(root)
	else:
		# 固定方針に寄せるなら、manifestから消してここで決め打ちでもよい
		message_script_roots = PackedStringArray([
			"res://addons/hakoniwa_msgs/"
		])

	if not manifest.has("extensions"):
		return _fail("Codec manifest has no 'extensions': %s" % codec_manifest_path)

	var exts = manifest["extensions"]
	if typeof(exts) != TYPE_ARRAY:
		return _fail("'extensions' must be an Array: %s" % codec_manifest_path)

	for ext_path_variant in exts:
		if typeof(ext_path_variant) != TYPE_STRING:
			return _fail("'extensions' must contain only String values")

		var ext_path := String(ext_path_variant)

		if ext_path.is_empty():
			return _fail("Codec manifest contains an empty extension path")

		if not FileAccess.file_exists(ext_path):
			if fail_fast:
				return _fail("Codec extension file not found: %s" % ext_path)
			push_warning("Codec extension file not found: %s" % ext_path)
			continue

		var already_loaded := GDExtensionManager.is_extension_loaded(ext_path)
		if already_loaded:
			skipped_extensions.append(ext_path)
		else:
			var status: int = GDExtensionManager.load_extension(ext_path)
			match status:
				GDExtensionManager.LOAD_STATUS_OK:
					loaded_extensions.append(ext_path)
				GDExtensionManager.LOAD_STATUS_ALREADY_LOADED:
					skipped_extensions.append(ext_path)
				_:
					var msg := "Failed to load codec extension: %s (status=%d)" % [ext_path, status]
					if fail_fast:
						return _fail(msg)
					push_warning(msg)
					continue
		# extension の loaded 状態とは別に、
		# この registry へ plugin を登録する必要がある
		var plugin_path := _to_registry_plugin_path(ext_path)
		if not _registry.load_plugin(plugin_path):
			var registry_error := "registry.load_plugin failed: %s" % ext_path
			if _registry.has_method("get_last_error"):
				var detail := String(_registry.get_last_error())
				if not detail.is_empty():
					registry_error = "%s: %s" % [registry_error, detail]
			if fail_fast:
				return _fail(registry_error)
			push_warning(registry_error)

	is_ready = true
	codec_manifest_loaded.emit()
	return true

func get_message_script_roots() -> PackedStringArray:
	return message_script_roots

func get_loaded_extensions() -> PackedStringArray:
	return loaded_extensions

func get_skipped_extensions() -> PackedStringArray:
	return skipped_extensions

func has_loaded_extension(path: String) -> bool:
	return loaded_extensions.has(path) or GDExtensionManager.is_extension_loaded(path)

func require_ready() -> void:
	if not is_ready:
		push_error("HakoniwaCodecNode is not ready: %s" % last_error)

func get_registry() -> Node:
	return _registry
	
	
func _ensure_registry() -> bool:
	if _registry != null:
		return true
	if not ClassDB.class_exists("HakoniwaCodecRegistry"):
		last_error = "HakoniwaCodecRegistry is not registered"
		return false
	_registry = ClassDB.instantiate("HakoniwaCodecRegistry") as Node
	if _registry == null:
		last_error = "HakoniwaCodecRegistry could not be instantiated"
		return false
	add_child(_registry)
	return true
	
func _to_registry_plugin_path(extension_path: String) -> String:
	if extension_path.ends_with(".gdextension"):
		return extension_path.trim_suffix(".gdextension")
	return extension_path

func _fail(message: String) -> bool:
	is_ready = false
	last_error = message
	push_error(message)
	codec_manifest_failed.emit(message)
	return false
