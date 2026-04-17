extends RefCounted

var _start_count := 0

func on_simulation_start() -> void:
	_start_count += 1
	if _start_count == 1:
		print("HAKO_CORE_SMOKE_START_CALLBACK")
	else:
		print("HAKO_CORE_SMOKE_RESTART_CALLBACK")

func on_simulation_stop() -> void:
	print("HAKO_CORE_SMOKE_STOP_CALLBACK")

func on_simulation_reset() -> void:
	print("HAKO_CORE_SMOKE_RESET_CALLBACK")
