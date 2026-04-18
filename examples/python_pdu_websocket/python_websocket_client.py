#!/usr/bin/env python3
import sys
import time
from pathlib import Path

from hakoniwa_pdu.pdu_msgs.geometry_msgs.pdu_conv_Twist import pdu_to_py_Twist, py_to_pdu_Twist
from hakoniwa_pdu.pdu_msgs.geometry_msgs.pdu_pytype_Twist import Twist
from hakoniwa_pdu_endpoint.c_endpoint import Endpoint, PduKey


def main() -> int:
    example_root = Path(__file__).resolve().parent
    config_path = example_root / "config" / "endpoint_websocket_client.json"

    endpoint = Endpoint("py_ws_client", "inout")
    recv_key = PduKey(robot="Robot", pdu="pos")
    send_key = PduKey(robot="Robot", pdu="motor")

    def on_recv(_resolved_key, payload):
        twist = pdu_to_py_Twist(payload)
        print(f"client recv pos: {twist}", flush=True)

    try:
        endpoint.open(str(config_path))
        endpoint.subscribe_on_recv_callback_by_name(recv_key, on_recv)
        endpoint.start()
        endpoint.post_start()
        time.sleep(1.0)

        send_count = 0
        while True:
            motor = Twist()
            motor.linear.x = 1001.0 + send_count
            motor.linear.y = 1002.0 + send_count
            motor.linear.z = 1003.0 + send_count
            endpoint.send_by_name(send_key, bytes(py_to_pdu_Twist(motor)))
            print(f"client sent motor: {motor}", flush=True)
            send_count += 1
            time.sleep(1.0)
    finally:
        try:
            endpoint.stop()
        except Exception:
            pass
        try:
            endpoint.close()
        except Exception:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
