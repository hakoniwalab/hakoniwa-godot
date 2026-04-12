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
create SimulationNode
  -> bind EndpointNode
create CodecRegistry Node
  -> load plugin(s)
create Endpoint Node
  -> open(config)
SimulationNode.initialize(asset_name)
  -> poll_event
  -> Start event
  -> Endpoint.start
  -> _physics_process で step
  -> Endpoint.process_recv_events
  -> recv / recv_next
  -> decode if needed
  -> Stop/Reset event
  -> Endpoint.stop
  -> Endpoint.close
  -> SimulationNode.shutdown
```

### time sync

```text
_ready
  -> codec load
  -> endpoint.open
  -> simulation.initialize

_physics_process
  -> simulation.poll_event
  -> if Start: endpoint.start
  -> if Running and world_time reached:
       endpoint.process_recv_events
       user simulation step
       simulation.notify_simtime(next_asset_time)
  -> if Stop: endpoint.stop
  -> if Reset: endpoint cleanup and scene reset

_exit_tree
  -> endpoint.stop
  -> endpoint.close
  -> simulation.shutdown
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

### codec plugin 利用

```text
CodecRegistry.load_plugin(hako_msgs_codec)
  -> Endpoint.open(config)
  -> Endpoint.start
  -> frame loop で recv
  -> CodecRegistry.decode(package, message, payload)
  -> アプリ側で Dictionary を利用
```

## Node ライフサイクルの最小例

```gdscript
extends Node

var endpoint: HakoniwaPduEndpoint
var codecs: HakoniwaCodecRegistry

func _ready() -> void:
	codecs = HakoniwaCodecRegistry.new()
	add_child(codecs)
	codecs.plugin_paths = PackedStringArray([
		"res://addons/hakoniwa/codecs/hako_msgs_codec",
	])

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

## wrapper 利用の最小例

```gdscript
const HakoniwaEndpointNode = preload("res://addons/hakoniwa/scripts/hakoniwa_pdu_endpoint.gd")
const HakoniwaSimulationNode = preload("res://addons/hakoniwa/scripts/hakoniwa_simulation_node.gd")

var endpoint: HakoniwaEndpointNode
var simulation: HakoniwaSimulationNode

func _ready() -> void:
	endpoint = HakoniwaEndpointNode.new()
	add_child(endpoint)
	endpoint.config_path = "res://config/endpoint_latest.json"
	endpoint.codec_plugins = PackedStringArray([
		"res://addons/hakoniwa/codecs/std_msgs_codec",
	])
	endpoint.load_configured_codecs()
	endpoint.open_endpoint()

	simulation = HakoniwaSimulationNode.new()
	add_child(simulation)
	simulation.asset_name = "GodotAsset"
	simulation.bind_endpoint(endpoint)
	simulation.initialize()

func _physics_process(_delta: float) -> void:
	if simulation.step():
		var record = endpoint.recv_message("drone0", "sample_state", "std_msgs", "UInt64")
		if not record.is_empty():
			print(record["value"]["data"])

func _exit_tree() -> void:
	endpoint.stop_endpoint()
	endpoint.close_endpoint()
	simulation.shutdown()
```

typed object を使う場合:

```gdscript
const HakoPduStdMsgsUInt64 = preload("res://messages/std_msgs/UInt64.gd")

func send_typed(endpoint: HakoniwaEndpointNode) -> void:
	var sample_state = endpoint.get_typed_endpoint("drone0", "sample_state")
	var msg = HakoPduStdMsgsUInt64.new()
	msg.data = 42
	sample_state.send(msg)

func recv_typed(endpoint: HakoniwaEndpointNode) -> void:
	var sample_state = endpoint.get_typed_endpoint("drone0", "sample_state")
	var msg = sample_state.recv()
	if msg != null:
		print(msg.data)
```

## 受信サンプル

`HakoniwaSimulationNode` を含む最小ライフサイクル:

```gdscript
extends Node

var simulation: HakoniwaSimulationNode
var endpoint: HakoniwaEndpointNode

func _ready() -> void:
	endpoint = HakoniwaEndpointNode.new()
	add_child(endpoint)
	endpoint.config_path = "res://config/endpoint_queue.json"
	endpoint.open_endpoint()

	simulation = HakoniwaSimulationNode.new()
	add_child(simulation)
	simulation.asset_name = "GodotAsset"
	simulation.bind_endpoint(endpoint)
	simulation.initialize()

func _physics_process(_delta: float) -> void:
	if simulation.step():
		while endpoint.get_pending_count() > 0:
			var record = endpoint.recv_next_raw()
			if record.is_empty():
				break
			print(record)

func _exit_tree() -> void:
	endpoint.stop_endpoint()
	endpoint.close_endpoint()
	simulation.shutdown()
```

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

## decode サンプル

plugin を `_ready()` でロードし、受信後に decode する最小例:

```gdscript
extends Node

@onready var codecs: HakoniwaCodecRegistry = $HakoniwaCodecRegistry
@onready var endpoint: HakoniwaPduEndpoint = $HakoniwaPduEndpoint

func _ready() -> void:
	codecs.plugin_paths = PackedStringArray([
		"res://addons/hakoniwa/codecs/hako_msgs_codec",
	])
	codecs.load_configured_plugins()
	endpoint.open("res://config/endpoint_latest.json")
	endpoint.start()

func _process(delta: float) -> void:
	endpoint.process_recv_events()
	var record = endpoint.recv_by_name("drone0", "game_controller")
	if record.is_empty():
		return
	var decoded = codecs.decode("hako_msgs", "GameControllerOperation", record["payload"])
	if not decoded.is_empty():
		print(decoded)

func _exit_tree() -> void:
	endpoint.stop()
	endpoint.close()
```

## encode サンプル

送信前に `Dictionary` を payload へ encode する最小例:

```gdscript
extends Node

@onready var codecs: HakoniwaCodecRegistry = $HakoniwaCodecRegistry
@onready var endpoint: HakoniwaPduEndpoint = $HakoniwaPduEndpoint

func send_game_controller(axis: PackedFloat64Array, button: Array) -> void:
	var value = {
		"axis": axis,
		"button": button,
	}
	var payload = codecs.encode("hako_msgs", "GameControllerOperation", value)
	if not payload.is_empty():
		endpoint.send_by_name("drone0", "game_controller", payload)
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
