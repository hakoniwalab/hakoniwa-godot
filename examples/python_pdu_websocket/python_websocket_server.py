#!/usr/bin/env python3
import sys
import time
from pathlib import Path

from hakoniwa_pdu.pdu_msgs.geometry_msgs.pdu_conv_Twist import pdu_to_py_Twist, py_to_pdu_Twist
from hakoniwa_pdu.pdu_msgs.geometry_msgs.pdu_pytype_Twist import Twist
from hakoniwa_pdu_endpoint.c_endpoint import Endpoint, PduKey


def main() -> int:
    example_root = Path(__file__).resolve().parent
    config_path = example_root / "config" / "endpoint_websocket_server.json"

    endpoint = Endpoint("py_ws_server", "inout")
    recv_key = PduKey(robot="Robot", pdu="motor")
    send_key = PduKey(robot="Robot", pdu="pos")
    received = []

    def on_recv(_resolved_key, payload):
        twist = pdu_to_py_Twist(payload)
        received.append(twist)
        print(f"server recv motor: {twist}", flush=True)

    try:
        endpoint.open(str(config_path))
        endpoint.subscribe_on_recv_callback_by_name(recv_key, on_recv)
        endpoint.start()
        endpoint.post_start()
        print("server started: waiting for motor on ws://0.0.0.0:54003/ws", flush=True)

        send_count = 0
        while True:
            if received:
                pos = Twist()
                pos.linear.x = send_count + 1
                pos.linear.y = send_count + 2
                pos.linear.z = send_count + 3
                endpoint.send_by_name(send_key, bytes(py_to_pdu_Twist(pos)))
                print(f"server sent pos: {pos}", flush=True)
                send_count += 1
                received.clear()
            time.sleep(0.1)
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
