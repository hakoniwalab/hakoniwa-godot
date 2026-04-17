#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import time

import hakopy
from hakoniwa_pdu.impl.shm_communication_service import ShmCommunicationService
from hakoniwa_pdu.pdu_manager import PduManager
from hakoniwa_pdu.pdu_msgs.std_msgs.pdu_conv_UInt64 import pdu_to_py_UInt64, py_to_pdu_UInt64
from hakoniwa_pdu.pdu_msgs.std_msgs.pdu_pytype_UInt64 import UInt64


PDU_GODOT_TO_PYTHON_CHANNEL_ID = 0
STEP_TARGET = 3
REPLY_VALUE = 1001

_pdu_manager = None
_recv_count = 0
_send_count = 0
_ok_printed = False


def _maybe_print_ok() -> None:
    global _ok_printed
    if _ok_printed:
        return
    if _recv_count >= STEP_TARGET and _send_count >= STEP_TARGET:
        _ok_printed = True
        print("HAKO_PYTHON_PDU_MINIMAL_PY_OK")


def on_recv(_recv_event_id):
    global _recv_count
    _pdu_manager.run_nowait()
    raw_data = _pdu_manager.read_pdu_raw_data("Robot", "godot_to_python")
    if raw_data is None or len(raw_data) == 0:
        print("HAKO_PYTHON_PDU_MINIMAL_PY_RECV_EMPTY")
        return 0
    value = pdu_to_py_UInt64(raw_data)
    if value is None:
        print("HAKO_PYTHON_PDU_MINIMAL_PY_RECV_DECODE_FAILED")
        return 0
    _recv_count += 1
    print(
        f"HAKO_PYTHON_PDU_MINIMAL_PY_RECV:{_recv_count}:simtime={hakopy.simulation_time()}:value={value.data}"
    )
    _maybe_print_ok()
    return 0


def my_on_initialize(_context):
    ret = hakopy.register_data_recv_event("Robot", PDU_GODOT_TO_PYTHON_CHANNEL_ID, on_recv)
    print(f"HAKO_PYTHON_PDU_MINIMAL_PY_REGISTER_RECV_EVENT:{ret}")
    return 0


def my_on_reset(_context):
    print("HAKO_PYTHON_PDU_MINIMAL_PY_RESET_CALLBACK")
    return 0


def my_on_manual_timing_control(_context):
    global _send_count
    result = True
    while result and _send_count < STEP_TARGET:
        value = UInt64()
        value.data = REPLY_VALUE + _send_count
        raw_data = py_to_pdu_UInt64(value)
        ok = _pdu_manager.flush_pdu_raw_data_nowait("Robot", "python_to_godot", raw_data)
        if not ok:
            print("HAKO_PYTHON_PDU_MINIMAL_PY_SEND_FAILED")
            break
        _send_count += 1
        print(
            f"HAKO_PYTHON_PDU_MINIMAL_PY_SEND:{_send_count}:simtime={hakopy.simulation_time()}:value={value.data}"
        )
        _maybe_print_ok()
        result = hakopy.usleep(20000)
        time.sleep(0.02)
    return 0


MY_CALLBACK = {
    "on_initialize": my_on_initialize,
    "on_simulation_step": None,
    "on_manual_timing_control": my_on_manual_timing_control,
    "on_reset": my_on_reset,
}


def main():
    global _pdu_manager
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <config_path>")
        return 1

    config_path = sys.argv[1]
    _pdu_manager = PduManager()
    _pdu_manager.initialize(
        config_path=config_path,
        comm_service=ShmCommunicationService(),
    )
    _pdu_manager.start_service_nowait()

    ret = hakopy.asset_register(
        "python_pdu_minimal_controller",
        config_path,
        MY_CALLBACK,
        20000,
        hakopy.HAKO_ASSET_MODEL_CONTROLLER,
    )
    if ret is False:
        print("HAKO_PYTHON_PDU_MINIMAL_PY_REGISTER_FAILED")
        return 1

    ret = hakopy.start()
    print(f"HAKO_PYTHON_PDU_MINIMAL_PY_START_RETURN:{ret}")
    _maybe_print_ok()
    return 0


if __name__ == "__main__":
    sys.exit(main())
