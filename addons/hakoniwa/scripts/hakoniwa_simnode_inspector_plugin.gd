@tool
extends EditorInspectorPlugin

const TARGET_SCRIPT_PATH := "res://addons/hakoniwa/scripts/hakoniwa_simulation_node.gd"
const TARGET_PROPERTY := "internal_endpoint_codec_packages"
const CODEC_DIR := "res://addons/hakoniwa/codecs"
const CODEC_SUFFIX := "_codec.gdextension"


class CodecPackageSelector:
	extends VBoxContainer

	var _target: Object = null
	var _property_name: String = ""
	var _checkboxes: Dictionary = {}
	var _updating := false
	var _list_container: VBoxContainer = null
	var _toggle_button: Button = null
	var _collapsed := true

	func setup(target: Object, property_name: String, package_names: PackedStringArray) -> void:
		_target = target
		_property_name = property_name

		var header := HBoxContainer.new()
		add_child(header)

		_toggle_button = Button.new()
		_toggle_button.text = _toggle_label()
		_toggle_button.flat = true
		_toggle_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_toggle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_toggle_button.pressed.connect(_toggle_collapsed)
		header.add_child(_toggle_button)

		var select_all_button := Button.new()
		select_all_button.text = "All"
		select_all_button.tooltip_text = "Select all installed codec packages."
		select_all_button.pressed.connect(_select_all)
		header.add_child(select_all_button)

		var clear_button := Button.new()
		clear_button.text = "Clear"
		clear_button.tooltip_text = "Clear all selected codec packages."
		clear_button.pressed.connect(_clear_all)
		header.add_child(clear_button)

		_list_container = VBoxContainer.new()
		add_child(_list_container)

		if package_names.is_empty():
			var empty := Label.new()
			empty.text = "No installed codec packages found under res://addons/hakoniwa/codecs."
			empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_list_container.add_child(empty)
			_list_container.visible = not _collapsed
			return

		var help := Label.new()
		help.text = "Select codec packages used by the internal SHM endpoint."
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list_container.add_child(help)

		for package_name in package_names:
			var checkbox := CheckBox.new()
			checkbox.text = package_name
			checkbox.toggled.connect(_on_toggled.bind(package_name))
			_list_container.add_child(checkbox)
			_checkboxes[package_name] = checkbox

		_refresh_from_object()
		_apply_collapsed_state()

	func _on_toggled(_pressed: bool, _package_name: String) -> void:
		if _updating or _target == null:
			return
		_write_selection()

	func _select_all() -> void:
		_updating = true
		for checkbox in _checkboxes.values():
			(checkbox as CheckBox).button_pressed = true
		_updating = false
		_write_selection()

	func _clear_all() -> void:
		_updating = true
		for checkbox in _checkboxes.values():
			(checkbox as CheckBox).button_pressed = false
		_updating = false
		_write_selection()

	func _write_selection() -> void:
		if _target == null:
			return
		var selected := PackedStringArray()
		var package_names: Array = _checkboxes.keys()
		package_names.sort()
		for package_name in package_names:
			var checkbox: CheckBox = _checkboxes[package_name]
			if checkbox.button_pressed:
				selected.append(package_name)
		_target.set(_property_name, selected)
		_update_toggle_text()

	func _toggle_collapsed() -> void:
		_collapsed = not _collapsed
		_apply_collapsed_state()

	func _apply_collapsed_state() -> void:
		if _list_container != null:
			_list_container.visible = not _collapsed
		_update_toggle_text()

	func _toggle_label() -> String:
		return "Internal Endpoint Codec Packages (%d selected)%s" % [
			_selected_count(),
			" ▸" if _collapsed else " ▾"
		]

	func _update_toggle_text() -> void:
		if _toggle_button != null:
			_toggle_button.text = _toggle_label()

	func _selected_count() -> int:
		var count := 0
		for checkbox in _checkboxes.values():
			if (checkbox as CheckBox).button_pressed:
				count += 1
		return count

	func _refresh_from_object() -> void:
		if _target == null:
			return
		_updating = true
		var selected_map := {}
		var current_value = _target.get(_property_name)
		for value in current_value:
			selected_map[str(value)] = true
		for package_name in _checkboxes.keys():
			var checkbox: CheckBox = _checkboxes[package_name]
			checkbox.button_pressed = selected_map.has(package_name)
		_updating = false
		_update_toggle_text()


func _can_handle(object: Object) -> bool:
	if object == null:
		return false
	var script := object.get_script()
	if script == null:
		return false
	return script.resource_path == TARGET_SCRIPT_PATH


func _parse_property(object: Object,
		_type: Variant.Type,
		name: String,
		_hint_type: PropertyHint,
		_hint_string: String,
		_usage_flags: int,
		_wide: bool) -> bool:
	if name != TARGET_PROPERTY:
		return false
	var selector := CodecPackageSelector.new()
	selector.setup(object, name, _find_installed_codec_packages())
	add_custom_control(selector)
	return true


func _find_installed_codec_packages() -> PackedStringArray:
	var package_names := PackedStringArray()
	var dir := DirAccess.open(CODEC_DIR)
	if dir == null:
		return package_names
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		if dir.current_is_dir():
			continue
		if not entry.ends_with(CODEC_SUFFIX):
			continue
		var package_name := entry.trim_suffix(CODEC_SUFFIX)
		if package_name.is_empty():
			continue
		package_names.append(package_name)
	dir.list_dir_end()
	package_names.sort()
	return package_names
