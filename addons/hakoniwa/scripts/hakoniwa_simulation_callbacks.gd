class_name HakoniwaSimulationCallbacks
extends RefCounted

func on_simulation_start() -> void:
	push_error("on_simulation_start() must be implemented")

func on_simulation_stop() -> void:
	push_error("on_simulation_stop() must be implemented")

func on_simulation_reset() -> void:
	push_error("on_simulation_reset() must be implemented")
