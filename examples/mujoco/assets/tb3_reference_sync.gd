extends "res://addons/hakoniwa_robot_sync/scripts/robot_sync_controller.gd"


func _ready() -> void:
	if sim_node_path.is_empty():
		sim_node_path = $"../HakoniwaSimNode".get_path()
	if target_root_path.is_empty():
		target_root_path = $"../RosToGodot".get_path()
	if profile_path.is_empty():
		profile_path = "res://config/robot_sync.profile.json"
	super._ready()
