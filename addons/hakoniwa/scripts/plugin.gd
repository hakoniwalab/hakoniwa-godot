@tool
extends EditorPlugin

const HakoniwaSimNodeInspectorPlugin = preload("res://addons/hakoniwa/scripts/hakoniwa_simnode_inspector_plugin.gd")

var _simnode_inspector_plugin = null

func _enter_tree() -> void:
	_simnode_inspector_plugin = HakoniwaSimNodeInspectorPlugin.new()
	add_inspector_plugin(_simnode_inspector_plugin)

func _exit_tree() -> void:
	if _simnode_inspector_plugin != null:
		remove_inspector_plugin(_simnode_inspector_plugin)
		_simnode_inspector_plugin = null
