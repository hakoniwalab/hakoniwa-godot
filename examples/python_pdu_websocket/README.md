# Python PDU WebSocket Example

このディレクトリには、`hakoniwa-pdu-endpoint` の WebSocket transport で `geometry_msgs/Twist` を双方向にやり取りする最小 Python 素材を置きます。

含まれるもの:

- `python_websocket_server.py`
  - WebSocket server 側
  - `motor` を受信して `pos` を返し続ける
- `python_websocket_client.py`
  - WebSocket client 側
  - `motor` を送信し続けて `pos` を受信する
- `config/`
  - WebSocket 用 endpoint config
  - `geometry_msgs/Twist` 用 PDU 定義

## 使う PDU

- `motor`
  - `geometry_msgs/Twist`
- `pos`
  - `geometry_msgs/Twist`

## 起動手順

```bash
# terminal 1
python examples/python_pdu_websocket/python_websocket_server.py

# terminal 2
python examples/python_pdu_websocket/python_websocket_client.py
```

## 成功時ログ

server:

```text
server started: waiting for motor on ws://0.0.0.0:54003/ws
server recv motor: Twist(...)
server sent pos: Twist(...)
server recv motor: Twist(...)
server sent pos: Twist(...)
```

client:

```text
client sent motor: Twist(...)
client recv pos: Twist(...)
client sent motor: Twist(...)
client recv pos: Twist(...)
```
