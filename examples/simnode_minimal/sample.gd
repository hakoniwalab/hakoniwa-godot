extends Node

@onready var sim: HakoniwaSimNode = $"./HakoniwaSimNode"

func _ready() -> void:
	sim.simulation_started.connect(_on_simulation_started)
	sim.simulation_step.connect(_on_simulation_step)

func _on_simulation_started() -> void:
	print("simulation started")

func _on_simulation_step(simtime_usec: int, world_time_usec: int) -> void:
	print("step simtime=%d world=%d" % [simtime_usec, world_time_usec])
