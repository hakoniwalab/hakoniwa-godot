extends RefCounted

var _pos_endpoint = null

func _init(pos_endpoint = null) -> void:
	_pos_endpoint = pos_endpoint

func on_simulation_start() -> void:
	var initial_pos := {
		"linear": {
			"x": 1.0,
			"y": 2.0,
			"z": 3.0
		},
		"angular": {
			"x": 0.0,
			"y": 0.0,
			"z": 0.0
		}
	}
	if _pos_endpoint != null:
		var result: int = _pos_endpoint.send_dict(initial_pos)
		if result != 0:
			push_error("initial pos send failed")
	print("HAKO_TWO_ASSET_START_CALLBACK")

func on_simulation_stop() -> void:
	print("HAKO_TWO_ASSET_STOP_CALLBACK")

func on_simulation_reset() -> void:
	print("HAKO_TWO_ASSET_RESET_CALLBACK")
