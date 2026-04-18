#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import sys
from pathlib import Path

import hakopy
from hakoniwa_pdu_endpoint.c_endpoint import Endpoint, PduKey
from hakoniwa_pdu.pdu_msgs.std_msgs.pdu_conv_UInt64 import pdu_to_py_UInt64, py_to_pdu_UInt64
from hakoniwa_pdu.pdu_msgs.std_msgs.pdu_pytype_UInt64 import UInt64


STEP_TARGET = 3
START_VALUE = 101
ASSET_NAME = "python_pdu_minimal_peer"
ENDPOINT_NAME = "python_pdu_minimal_peer_endpoint"
GODOT_TO_PYTHON_KEY = PduKey(robot="Robot", pdu="godot_to_python")
PYTHON_TO_GODOT_KEY = PduKey(robot="Robot", pdu="python_to_godot")

_endpoint = None
_endpoint_started = False
_step_count = 0
_recv_count = 0
_ok_printed = False


def _maybe_print_ok() -> None:
    global _ok_printed
    if _ok_printed:
        return
    if _step_count >= STEP_TARGET and _recv_count >= STEP_TARGET:
        _ok_printed = True
        print("HAKO_PYTHON_PDU_MINIMAL_PEER_OK")


def _resolve_paths(config_path: str) -> tuple[str, str]:
    config_file = Path(config_path).resolve()
    root = json.loads(config_file.read_text())

    if isinstance(root, dict) and "pdu_def_path" in root:
        endpoint_config_path = config_file
        pdu_def_path = (config_file.parent / root["pdu_def_path"]).resolve()
        return (str(endpoint_config_path), str(pdu_def_path))

    if isinstance(root, dict) and "paths" in root and "robots" in root:
        endpoint_config_path = config_file.parent.parent / "endpoint_shm_with_pdu_python_peer.json"
        return (str(endpoint_config_path.resolve()), str(config_file))

    raise ValueError(f"Unsupported config format: {config_file}")


def _on_python_message(event) -> None:
    global _recv_count

    value = pdu_to_py_UInt64(event.payload)
    if value is None:
        print("HAKO_PYTHON_PDU_MINIMAL_PEER_RECV_DECODE_FAILED")
        return

    _recv_count += 1
    print(
        f"HAKO_PYTHON_PDU_MINIMAL_PEER_RECV:{_recv_count}:simtime={hakopy.simulation_time()}:value={value.data}"
    )
    _maybe_print_ok()


def my_on_initialize(_context):
    global _endpoint_started

    if _endpoint is None:
        print("HAKO_PYTHON_PDU_MINIMAL_PEER_ENDPOINT_NOT_READY")
        return -1

    if _endpoint_started:
        return 0

    _endpoint.on_recv_by_name(PYTHON_TO_GODOT_KEY, _on_python_message)
    _endpoint.post_start()
    _endpoint.start_dispatch()
    _endpoint_started = True
    print("HAKO_PYTHON_PDU_MINIMAL_PEER_ENDPOINT_READY")
    return 0


def my_on_reset(_context):
    print("HAKO_PYTHON_PDU_MINIMAL_PEER_RESET_CALLBACK")
    return 0


def my_on_manual_timing_control(_context):
    global _step_count

    if _endpoint is None or not _endpoint_started:
        print("HAKO_PYTHON_PDU_MINIMAL_PEER_ENDPOINT_NOT_STARTED")
        return -1

    _endpoint.process_recv_events()

    if _step_count >= STEP_TARGET:
        _maybe_print_ok()
        return 0

    value = UInt64()
    value.data = START_VALUE + _step_count
    raw_data = py_to_pdu_UInt64(value)
    _endpoint.send_by_name(GODOT_TO_PYTHON_KEY, raw_data)

    _step_count += 1
    print(
        f"HAKO_PYTHON_PDU_MINIMAL_PEER_SEND:{_step_count}:simtime={hakopy.simulation_time()}:value={value.data}"
    )
    _maybe_print_ok()
    return 0


MY_CALLBACK = {
    "on_initialize": my_on_initialize,
    "on_simulation_step": None,
    "on_manual_timing_control": my_on_manual_timing_control,
    "on_reset": my_on_reset,
}


def main():
    global _endpoint

    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <endpoint_config_or_pdu_def_path>")
        return 1

    endpoint_config_path, asset_config_path = _resolve_paths(sys.argv[1])

    _endpoint = Endpoint(ENDPOINT_NAME, "inout")
    _endpoint.open(endpoint_config_path)

    ret = hakopy.asset_register(
        ASSET_NAME,
        asset_config_path,
        MY_CALLBACK,
        20000,
        hakopy.HAKO_ASSET_MODEL_PLANT,
    )
    if ret is False:
        print("HAKO_PYTHON_PDU_MINIMAL_PEER_REGISTER_FAILED")
        return 1

    _endpoint.start()

    while True:
        ret = hakopy.start()
        print(f"HAKO_PYTHON_PDU_MINIMAL_PEER_START_RETURN:{ret}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
