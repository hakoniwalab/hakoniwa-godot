# Python PDU WebSocket Example

このディレクトリには、`hakoniwa-pdu-endpoint` の WebSocket transport で `geometry_msgs/Twist` を双方向にやり取りする最小素材を置きます。

含まれるもの:

- `sample.gd`
  - Godot 側の最小 script
  - `HakoniwaCodecNode` と `HakoniwaEndpointNode` を前提に、`motor` を送信し `pos` を受信する
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

この example では、scene に次の 2 つを置く前提です。

- `HakoniwaCodecNode`
- `HakoniwaEndpointNode`

`HakoniwaCodecNode` は codec と typed message script の所有者です。  
`HakoniwaEndpointNode` は通信だけを担当し、`CodecNode` を参照します。

### `HakoniwaCodecNode`

- `Codec Manifest Path`
  - `res://addons/hakoniwa/codec_manifest.json`
- `Load On Ready`
  - `On`

### `HakoniwaEndpointNode`

- `Config Path`
  - `res://config/endpoint_websocket_client.json`
- `Codec Node Path`
  - `../HakoniwaCodecNode`
- `Start on Ready`
  - `On`
- `Auto Process Recv Events`
  - `On`

`sample.gd` は `endpoint_ready` signal を受けて typed endpoint bind と subscription を行う前提です。  
`config_path` が設定されていれば、endpoint は `_ready()` で `prepare()` され、`endpoint_ready` 後に `Start on Ready` が有効なら自動 `start/post_start` まで進みます。

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
