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

## Godot 側の設定メモ

`HakoniwaEndpointNode` を使う場合、通常は次を設定します。

- `Config Path`
  - `res://config/endpoint_websocket_client.json`
- `Codec Plugins`
  - `geometry_msgs`
- `Start on Ready`
  - `On`
- `Auto Process Recv Events`
  - `On`

`Message Script Roots` は通常はデフォルトのままで構いません。
`addons/hakoniwa_msgs` 以外に generated message script を置いている場合だけ変更します。

例:

```gdscript
endpoint.message_script_roots = PackedStringArray([
	"res://addons/hakoniwa_msgs"
])
```

`sample.gd` は `endpoint_ready` signal を受けて typed endpoint bind と subscription を行う前提です。  
`config_path` が設定されていれば、endpoint は `_ready()` で自動 `open` されます。

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
