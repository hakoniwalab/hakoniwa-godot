#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import time
import json
import os

import hakopy
from hakoniwa_pdu.pdu_msgs.geometry_msgs.pdu_conv_Twist import py_to_pdu_Twist, pdu_to_py_Twist
from hakoniwa_pdu.pdu_msgs.geometry_msgs.pdu_pytype_Twist import Twist
from hakoniwa_pdu_endpoint.c_endpoint import Endpoint, PduKey


_endpoint = None

def on_recv(resolved_key, payload):
    py_obj = pdu_to_py_Twist(payload) 
    print(resolved_key.robot, resolved_key.channel_id, py_obj)

def my_on_initialize(_context):
    global _endpoint
    try:
        recv_key = PduKey(robot="Robot", pdu="pos")
        _endpoint.subscribe_on_recv_callback_by_name(recv_key, on_recv)
        _endpoint.post_start()
        print("HAKO_PYTHON_EP_POST_START_OK")
    except Exception as exc:
        print(f"HAKO_PYTHON_EP_POST_START_FAILED:{exc}")
        return -1
    return 0


def my_on_reset(_context):
    print("HAKO_PYTHON_EP_RESET_CALLBACK")
    return 0


def my_on_manual_timing_control(_context):
    global _endpoint
    key = PduKey(robot="Robot", pdu="motor")
    motor = Twist()
    count = 0
    result = True
    while result:
        motor.linear.x = count + 1001
        motor.linear.y = count + 1002
        motor.linear.z = count + 1003
        payload = bytes(py_to_pdu_Twist(motor))
        try:
            _endpoint.send_by_name(key, payload)
        except Exception as exc:
            print(f"HAKO_PYTHON_EP_WRITE_MOTOR_FAILED:{exc}")
            #skip sleep and retry immediately
        print(
            f"HAKO_PYTHON_EP_WRITE_MOTOR:{hakopy.simulation_time()}:{motor.linear.x},{motor.linear.y},{motor.linear.z}"
        )
        result = hakopy.usleep(20000)
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
    global _endpoint
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <pdu_config_path>")
        return 1

    config_path = sys.argv[1]

    dir_path = os.path.dirname(config_path)
    ep_config = json.load(open(config_path))
    pdu_config_path = ep_config.get("pdu_def_path")
    if pdu_config_path is None:
        print("HAKO_PYTHON_EP_NO_PDU_CONFIG_PATH")
        return 1
    pdu_config_path = os.path.join(dir_path, pdu_config_path)

    _endpoint = Endpoint("python_pdu_minimal_ep", "inout")
    try:
        _endpoint.open(config_path)
        _endpoint.start()
        print("HAKO_PYTHON_EP_ENDPOINT_READY")
    except Exception as exc:
        print(f"HAKO_PYTHON_EP_ENDPOINT_OPEN_FAILED:{exc}")
        return 1

    ret = hakopy.asset_register(
        "python_core_pro_controller",
        pdu_config_path,
        MY_CALLBACK,
        20000,
        hakopy.HAKO_ASSET_MODEL_CONTROLLER,
    )
    if ret is False:
        print("HAKO_PYTHON_EP_REGISTER_FAILED")
        return 1

    try:
        while True:
            ret = hakopy.start()
            print(f"HAKO_PYTHON_EP_START_RETURN:{ret}")
            break
    finally:
        try:
            _endpoint.stop()
        except Exception:
            pass
        try:
            _endpoint.close()
        except Exception:
            pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
