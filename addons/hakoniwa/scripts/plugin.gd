@tool
extends EditorPlugin

const HakoniwaSimNodeInspectorPlugin = preload("res://addons/hakoniwa/scripts/hakoniwa_simnode_inspector_plugin.gd")
const HakoniwaEndpointInspectorPlugin = preload("res://addons/hakoniwa/scripts/hakoniwa_endpoint_inspector_plugin.gd")

var _simnode_inspector_plugin = null
var _endpoint_inspector_plugin = null

func _enter_tree() -> void:
	_simnode_inspector_plugin = HakoniwaSimNodeInspectorPlugin.new()
	_simnode_inspector_plugin.set_editor_plugin(self)
	add_inspector_plugin(_simnode_inspector_plugin)
	_endpoint_inspector_plugin = HakoniwaEndpointInspectorPlugin.new()
	_endpoint_inspector_plugin.set_editor_plugin(self)
	add_inspector_plugin(_endpoint_inspector_plugin)

func _exit_tree() -> void:
	if _endpoint_inspector_plugin != null:
		remove_inspector_plugin(_endpoint_inspector_plugin)
		_endpoint_inspector_plugin = null
	if _simnode_inspector_plugin != null:
		remove_inspector_plugin(_simnode_inspector_plugin)
		_simnode_inspector_plugin = null
