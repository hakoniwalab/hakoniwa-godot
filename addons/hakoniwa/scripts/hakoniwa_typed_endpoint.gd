class_name HakoniwaTypedEndpoint
extends RefCounted

var _endpoint = null
var _robot: String = ""
var _pdu_name: String = ""
var _package_name: String = ""
var _message_name: String = ""

func setup(endpoint,
		robot: String,
		pdu_name: String,
		package_name: String,
		message_name: String):
	_endpoint = endpoint
	_robot = robot
	_pdu_name = pdu_name
	_package_name = package_name
	_message_name = message_name
	return self

func get_robot() -> String:
	return _robot

func get_pdu_name() -> String:
	return _pdu_name

func get_package_name() -> String:
	return _package_name

func get_message_name() -> String:
	return _message_name

func send(typed_value: Variant) -> int:
	if _endpoint == null:
		return -1
	return _endpoint.send_typed_message(_robot, _pdu_name, _package_name, _message_name, typed_value)

func recv() -> Variant:
	if _endpoint == null:
		return null
	var record: Dictionary = _endpoint.recv_typed_message(_robot, _pdu_name, _package_name, _message_name)
	if record.is_empty():
		return null
	return record.get("typed_value", null)

func recv_record() -> Dictionary:
	if _endpoint == null:
		return {}
	return _endpoint.recv_typed_message(_robot, _pdu_name, _package_name, _message_name)

func send_dict(value: Dictionary) -> int:
	if _endpoint == null:
		return -1
	return _endpoint.send_message(_robot, _pdu_name, _package_name, _message_name, value)

func recv_dict() -> Dictionary:
	if _endpoint == null:
		return {}
	var record: Dictionary = _endpoint.recv_message(_robot, _pdu_name, _package_name, _message_name)
	if record.is_empty():
		return {}
	return record.get("value", {})
