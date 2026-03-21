# API Sequences

## 目的

利用者が API の呼び出し順を誤らないように、代表的な利用シーケンスを示す。

## この文書に含める内容

- 初期化シーケンス
- 接続開始シーケンス
- `latest` モード利用シーケンス
- `queue` モード利用シーケンス
- 停止と破棄のシーケンス
- エラー時の分岐

## 初期シーケンス案

### 起動

```text
create Node
  -> open(config)
  -> start
  -> process_recv_events
  -> recv / recv_next
  -> stop
  -> close
```

### latest

```text
_ready
  -> open(config_latest)
  -> start

_process
  -> process_recv_events
  -> recv(key) or poll_latest

_exit_tree
  -> stop
  -> close
```

### queue

```text
_ready
  -> open(config_queue)
  -> start
  -> set_recv_event(optional)

_physics_process or _process
  -> process_recv_events
  -> get_pending_count
  -> recv_next
  -> recv_next

_exit_tree
  -> stop
  -> close
```

### 複数 endpoint

```text
EndpointA.open(config_ws)
EndpointB.open(config_shm)
  -> EndpointA.start
  -> EndpointB.start
  -> frame loop で各 endpoint を個別に process / recv
  -> EndpointA.stop
  -> EndpointB.stop
  -> EndpointA.close
  -> EndpointB.close
```

## Node ライフサイクルの最小例

```gdscript
extends Node

var endpoint: HakoniwaPduEndpoint

func _ready() -> void:
	endpoint = HakoniwaPduEndpoint.new()
	add_child(endpoint)
	endpoint.open("res://config/endpoint_ws.json")
	endpoint.start()

func _process(delta: float) -> void:
	endpoint.process_recv_events()

func _exit_tree() -> void:
	endpoint.stop()
	endpoint.close()
```

## 受信サンプル

`queue` モードを毎フレーム drain する最小例:

```gdscript
extends Node

var endpoint: HakoniwaPduEndpoint

func _ready() -> void:
	endpoint = HakoniwaPduEndpoint.new()
	add_child(endpoint)
	endpoint.open("res://config/endpoint_queue.json")
	endpoint.start()
	endpoint.set_recv_event("drone0", 0)

func _process(delta: float) -> void:
	endpoint.process_recv_events()

	while endpoint.get_pending_count() > 0:
		var record = endpoint.recv_next()
		if record.is_empty():
			break
		print(record)

func _exit_tree() -> void:
	endpoint.stop()
	endpoint.close()
```

期待する挙動:

```text
send x 3
  -> pending_count = 3
recv_next x 1
  -> pending_count = 2
recv_next x 1
  -> pending_count = 1
recv_next x 1
  -> pending_count = 0
```

`latest` モードで名前指定受信する最小例:

```gdscript
extends Node

var endpoint: HakoniwaPduEndpoint

func _ready() -> void:
	endpoint = HakoniwaPduEndpoint.new()
	add_child(endpoint)
	endpoint.open("res://config/endpoint_latest.json")
	endpoint.start()

func _process(delta: float) -> void:
	endpoint.process_recv_events()
	var value = endpoint.recv_by_name("drone0", "pose")
	if not value.is_empty():
		print(value)

func _exit_tree() -> void:
	endpoint.stop()
	endpoint.close()
```

## 送信サンプル

送信 API を追加した後は、以下の形を基本例とする。

```gdscript
extends Node

var endpoint: HakoniwaPduEndpoint

func _ready() -> void:
	endpoint = HakoniwaPduEndpoint.new()
	add_child(endpoint)
	endpoint.open("res://config/endpoint_out.json")
	endpoint.start()

func send_command(payload: PackedByteArray) -> void:
	endpoint.send_by_name("drone0", "cmd_vel", payload)

func _exit_tree() -> void:
	endpoint.stop()
	endpoint.close()
```
