extends Node

func _ready() -> void:
	var extension: Resource = load("res://addons/hakoniwa/hakoniwa.gdextension")
	if extension == null:
		push_error("hakoniwa.gdextension could not be loaded")
		return

	if not ClassDB.class_exists("HakoniwaPduEndpoint"):
		push_error("HakoniwaPduEndpoint is not registered")
		return

	var endpoint := ClassDB.instantiate("HakoniwaPduEndpoint") as Node
	if endpoint == null:
		push_error("HakoniwaPduEndpoint could not be instantiated")
		return

	print(endpoint.call("get_backend_name"))
	print(endpoint.call("probe_native_backend"))
	add_child(endpoint)
	endpoint.queue_free()
