#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import time

import hakopy
from hakoniwa_pdu.impl.shm_communication_service import ShmCommunicationService
from hakoniwa_pdu.pdu_manager import PduManager
from hakoniwa_pdu.pdu_msgs.geometry_msgs.pdu_conv_Twist import pdu_to_py_Twist, py_to_pdu_Twist
from hakoniwa_pdu.pdu_msgs.geometry_msgs.pdu_pytype_Twist import Twist


PDU_MOTOR_CHANNEL_ID = 0
PDU_POS_CHANNEL_ID = 1

_pdu_manager = None


def on_recv(_recv_event_id):
    global _pdu_manager
    _pdu_manager.run_nowait()
    raw_data = _pdu_manager.read_pdu_raw_data("Robot", "pos")
    if raw_data is None or len(raw_data) == 0:
        print("HAKO_TWO_ASSET_PY_READ_POS_EMPTY")
        return 0
    pos = pdu_to_py_Twist(raw_data)
    if pos is None:
        print("HAKO_TWO_ASSET_PY_READ_POS_FAILED")
        return 0
    print(
        f"HAKO_TWO_ASSET_PY_READ_POS:{hakopy.simulation_time()}:{pos.linear.x},{pos.linear.y},{pos.linear.z}"
    )
    return 0


def my_on_initialize(_context):
    ret = hakopy.register_data_recv_event("Robot", PDU_POS_CHANNEL_ID, on_recv)
    print(f"HAKO_TWO_ASSET_PY_REGISTER_RECV_EVENT:{ret}")
    return 0


def my_on_reset(_context):
    print("HAKO_TWO_ASSET_PY_RESET_CALLBACK")
    return 0


def my_on_manual_timing_control(_context):
    global _pdu_manager
    motor = Twist()
    count = 0
    result = True
    while result:
        motor.linear.x = count + 1001
        motor.linear.y = count + 1002
        motor.linear.z = count + 1003
        raw_data = py_to_pdu_Twist(motor)
        ok = _pdu_manager.flush_pdu_raw_data_nowait("Robot", "motor", raw_data)
        if not ok:
            print("HAKO_TWO_ASSET_PY_WRITE_MOTOR_FAILED")
            break
        print(
            f"HAKO_TWO_ASSET_PY_WRITE_MOTOR:{hakopy.simulation_time()}:{motor.linear.x},{motor.linear.y},{motor.linear.z}"
        )
        result = hakopy.usleep(20000)
        time.sleep(0.02)
        if not result:
            break
        count += 1
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
        "python_core_pro_controller",
        config_path,
        MY_CALLBACK,
        20000,
        hakopy.HAKO_ASSET_MODEL_CONTROLLER,
    )
    if ret is False:
        print("HAKO_TWO_ASSET_PY_REGISTER_FAILED")
        return 1

    ret = hakopy.start()
    print(f"HAKO_TWO_ASSET_PY_START_RETURN:{ret}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
