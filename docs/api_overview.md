# API Overview

## 目的

利用者が `hakoniwa-godot` の入口 API を短時間で理解できるようにする。

## この文書に含める内容

- 公開クラスの一覧
- 各クラスの責務
- `latest` / `queue` の使い分け
- 利用開始までの最短パス
- 典型的な利用パターン

## 初期方針

最初の公開 API は最小限に抑える。

候補:

- `HakoniwaCoreAsset`
- `HakoniwaSimNode`
- `HakoniwaPduEndpoint`
- `HakoniwaCodecRegistry`
- `HakoniwaEndpointNode`
- `HakoniwaTypedEndpoint`

時間同期は `HakoniwaCoreAsset` / `HakoniwaSimNode`、通信は `HakoniwaPduEndpoint`、codec plugin のロードと decode / encode は `HakoniwaCodecRegistry` に分ける。
一般利用者向けには、主入口として `HakoniwaSimNode` を提供する。`HakoniwaEndpointNode` は独立利用または advanced use とする。`HakoniwaCodecRegistry` の直接利用は low-level API とみなし、通常利用では推奨しない。

## 利用形態

`HakoniwaCoreAsset` と `HakoniwaPduEndpoint` / `HakoniwaCodecRegistry` は Godot の `Node` として提供する。
加えて、`HakoniwaSimNode` を GDScript 側の主 wrapper として提供する。

利用者は以下のどちらかの形で使う。

1. シーンに `HakoniwaSimNode` ノードを配置する
2. 必要なら WebSocket など別 transport 用に `HakoniwaEndpointNode` を追加する
3. スクリプトから必要な Node を生成する

`HakoniwaSimNode` は時間同期の主ノードであり、必要に応じて SHM endpoint を内部で持てる。`HakoniwaPduEndpoint` は外部通信専用ノード、`HakoniwaCodecRegistry` は message codec 管理ノードとして扱う。

## 基本責務

`HakoniwaCoreAsset` の責務は以下とする。

- `hakoniwa-core-pro` polling API の native wrapper
- asset register / unregister
- start / stop / reset event の取得
- world time の取得
- simtime notify
- simulation state の取得

`HakoniwaSimNode` の責務は以下とする。

- `HakoniwaCoreAsset` の所有
- Godot の lifecycle と箱庭 lifecycle の接続
- `_physics_process()` での simulation step 制御
- オプションで SHM endpoint の start / stop / pump 制御
- callback 実行と `tick() -> bool` による step gate
- `asset_name` と内部 SHM endpoint の `asset_name` 整合管理

`HakoniwaSimNode` は single-asset model を前提とする。

- 1 Godot application = 1 Hakoniwa asset
- 同一アプリで複数 instance は許可しない
- 2 個目以降の初期化はエラー扱いにする

`HakoniwaPduEndpoint` の責務は以下とする。

- endpoint の生成と破棄
- config に基づく open / close
- start / stop
- `process_recv_events()` の呼び出し
- `recv()` / `recv_next()` 相当の pull API 提供

`HakoniwaCodecRegistry` の責務は以下とする。

- codec plugin の動的ロード
- package / message ごとの codec の存在判定
- `PackedByteArray -> Dictionary` の decode
- `Dictionary -> PackedByteArray` の encode
- plugin 未導入時の fallback 判定

`HakoniwaEndpointNode` の責務は以下とする。

- native `HakoniwaPduEndpoint` と `HakoniwaCodecRegistry` の生成
- codec plugin の初期ロード
- codec plugin に対応する `.gdextension` resource の初期化吸収
- `open / start / stop / close` の簡略化
- `send_message()` / `recv_message()` / `recv_next_message()` による encode/decode 付き API 提供
- `send_typed_message()` / `recv_typed_message()` による GDScript typed object API 提供
- `get_typed_endpoint(robot, pdu_name)` による PDU 特化 endpoint の生成

`HakoniwaTypedEndpoint` の責務は以下とする。

- 特定の `robot + pdu_name` に束縛された送受信
- `pdu_def` に基づく型解決結果の保持
- `send()` / `recv()` の単純 API 提供

Godot オブジェクト更新そのものは、このノードの責務ではない。

受信結果をどう各ゲームオブジェクトへ反映するかは、利用者側のスクリプトまたは上位ノードが行う。

## 利用者から見た最小パターン

```text
SimNode を作る
  -> asset_name を設定する
  -> 必要なら internal SHM endpoint を有効化する
  -> initialize する
  -> _physics_process で tick する
  -> tick() == true のときだけ simulation 処理を進める
  -> 終了時に shutdown する

WebSocket 等を使う場合:
  -> 独立した EndpointNode を追加する
  -> SimNode とは別に open / start / recv / send する
```

## 複数インスタンス方針

`HakoniwaPduEndpoint` は複数インスタンス可能とする。

基本単位は以下。

```text
1 Node = 1 native endpoint handle
```

したがって、以下のような構成を許可する。

- 1 つの endpoint をアプリ全体で共有する
- transport ごとに endpoint を分ける
- mode ごとに endpoint を分ける
- scene ごとに endpoint を分ける

例:

- WebSocket 用 endpoint
- SHM 用 endpoint
- `latest` 用 endpoint
- `queue` 用 endpoint

一方で、`HakoniwaSimNode` は複数インスタンスを許可しない。

理由:

- Godot アプリ全体を 1 Hakoniwa asset として扱うため
- simulation state と world time は process 単位の責務だから
- 複数 simulation node を許すと asset 名と lifecycle が衝突するため

## 1アプリに1個だけ置くべきか

単純な用途では 1 アプリに 1 個でもよい。

ただし、この制約を API 側で強制しない。

理由:

- transport が異なる endpoint を分離したいケースがある
- 受信モードを分けたいケースがある
- シーン構成や責務分離の単位で分けたいケースがある

## 通信時の基本制約

Godot 向け統合では、以下を基本制約とする。

### 1. 受信は pull 型を基本にする

Godot 側の主 API は callback 主体ではなく、利用者が明示的に呼ぶ pull API とする。

理由:

- Godot の main loop に揃えやすい
- transport ごとの callback タイミング差を隠蔽できる
- `hakoniwa-pdu-endpoint` の設計方針と一致する

### 2. `process_recv_events()` を main loop から呼べるようにする

特に SHM poll 系では、`process_recv_events()` が受信進行に必要になる。

そのため、利用者は `_process()` または `_physics_process()` からこれを呼べる必要がある。

### 3. 別スレッド callback から直接 Godot オブジェクトを触らない

native 側で callback が発火しうるとしても、Godot の scene tree や Node を直接更新する API にはしない。

Godot 側の更新は、caller-controlled なタイミングで行う。

## 推奨利用モデル

初期実装では、以下を推奨利用モデルとする。

- 初期化は `_ready()`
- 時間同期の定期処理は `_physics_process()`
- 描画や UI は `_process()`
- 終了処理は `_exit_tree()`
- codec plugin のロードは endpoint の `start()` より前
- endpoint の start は simulation `Start` event 後
- codec plugin path は `res://addons/hakoniwa/codecs/<package>_codec` のように拡張子なしを推奨する

## codec plugin 利用境界

通常利用者は、codec plugin 初期化順を意識しない形で使うべきである。

- 推奨:
  - `HakoniwaSimNode`
  - `HakoniwaEndpointNode`
- advanced / low-level:
  - `HakoniwaCodecRegistry`
  - native codec loader

`HakoniwaEndpointNode` は plugin path に対応する `.gdextension` を先にロードしてから codec を有効化する。
一方で、`HakoniwaCodecRegistry` を直接使う場合は、その前提を呼び出し側が理解している必要がある。

## Node ライフサイクル対応

Godot 利用者が迷わないように、`HakoniwaPduEndpoint` は以下のライフサイクル対応を前提に設計する。

### `HakoniwaSimNode`

#### `_ready()`

- `asset_name` を確定する
- `initialize()` を呼ぶ
- `initialize()` の内部で `HakoniwaCoreAsset` 初期化と polling asset register を行う
- `use_internal_shm_endpoint == true` の場合は内部 SHM endpoint を準備する

#### `_physics_process()`

- `tick()` を呼ぶ
- `tick()` の内部で event check と callback を行う
- `tick() == true` のフレームだけ simulation 処理を進める

#### `_exit_tree()`

- 内部 SHM endpoint があれば停止する
- asset を unregister する

### `_ready()`

- codec plugin を `load_plugin(...)` または `load_configured_plugins()` でロードする
- endpoint を `open(...)` する
- 必要なら `set_recv_event(...)` を設定する
- `start()` する
- transport に応じて `post_start()` を呼ぶ余地を残す

### `_process()` または `_physics_process()`

- `process_recv_events()` を呼ぶ
- `recv_by_name(...)` または `recv_next()` を呼ぶ
- 受信した結果を上位ノードへ渡す

### `_exit_tree()`

- `stop()` する
- `close()` する

## 利用者コードの責務

利用者コードは以下を担当する。

- `SimNode` を 1 個だけ配置する
- asset 名を決める
- どの simulation step でゲームロジックを動かすか決める
- SHM endpoint を内部オプションとして使うか決める
- 他 transport を使うなら独立 endpoint をどう構成するか決める
- どの key を読むか決める
- どの codec package をロードするか決める
- 受信した `Dictionary` や `PackedByteArray` をアプリ側の型へ変換する
- シーン内の各 Node に結果を反映する

`HakoniwaCoreAsset` は時間同期ノード、`HakoniwaPduEndpoint` は通信ノード、`HakoniwaCodecRegistry` は decode 補助ノードである。いずれもゲームロジックや表示更新そのものは持たない。
`HakoniwaSimNode` はそれらの一部を利用しやすく束ねる主入口であり、特に `hakoniwa-core-pro` と SHM endpoint の整合を吸収する。

## 利用者は endpoint をどう取得するか

Godot 利用者は、通常の Node 参照と同じ方法で `HakoniwaPduEndpoint` を取得する。

`HakoniwaCodecRegistry` も同じ取得モデルとする。

想定する取得パターンは以下。

### 1. 同一シーン内の Node を直接参照する

もっとも単純な形。

```gdscript
@onready var endpoint = $HakoniwaPduEndpoint
```

または:

```gdscript
@onready var endpoint = get_node("HakoniwaPduEndpoint")
```

### 2. 親ノードまたは manager ノードから受け取る

責務分離をしたい場合は、endpoint の所有者と利用者を分ける。

```gdscript
var endpoint: HakoniwaPduEndpoint

func setup(ep: HakoniwaPduEndpoint) -> void:
	endpoint = ep
```

この形では、上位ノードが endpoint の open / start / stop を管理する。

### 3. アプリ全体の共有 endpoint として参照する

アプリ全体で 1 個の endpoint を共有したい場合は、Autoload または共有 manager ノード経由で参照する。

この場合でも、API 上は単なる `HakoniwaPduEndpoint` 参照として扱う。

## 利用者はどう送受信するか

利用者は、取得した `HakoniwaPduEndpoint` 参照に対してメソッドを呼ぶ。

### 受信

受信の基本形:

```gdscript
func _process(delta: float) -> void:
	endpoint.process_recv_events()

	while endpoint.get_pending_count() > 0:
		var record = endpoint.recv_next()
		if record.is_empty():
			break
		print(record)
```

最新値を読む形:

```gdscript
func _process(delta: float) -> void:
	endpoint.process_recv_events()
	var value = endpoint.recv_by_name("drone0", "pose")
	if not value.is_empty():
		print(value)
```

codec plugin を使う形:

```gdscript
@onready var codecs: HakoniwaCodecRegistry = $HakoniwaCodecRegistry

func _process(delta: float) -> void:
	endpoint.process_recv_events()
	var record = endpoint.recv_by_name("drone0", "game_controller")
	if record.is_empty():
		return
	var decoded = codecs.decode("hako_msgs", "GameControllerOperation", record["payload"])
	if not decoded.is_empty():
		print(decoded)
```

### 送信

送信 API を追加した後は、以下のように利用する。

```gdscript
func send_command(payload: PackedByteArray) -> void:
	endpoint.send_by_name("drone0", "cmd_vel", payload)
```

codec plugin を使う送信形:

```gdscript
func send_gamepad(axis: PackedFloat64Array, button: Array) -> void:
	var value = {
		"axis": axis,
		"button": button,
	}
	var payload = codecs.encode("hako_msgs", "GameControllerOperation", value)
	if not payload.is_empty():
		endpoint.send_by_name("drone0", "game_controller", payload)
```

## 所有者と利用者を分ける方針

設計上は、endpoint を生成・開始する Node と、実際に送受信を利用する Node を分けてもよい。

推奨方針:

- endpoint の所有者が `open / start / stop / close` を担当する
- 利用者 Node は endpoint 参照を受け取って `send / recv` を使う

これにより、複数 Node が同じ endpoint を安全に共有しやすくなる。

同じ考え方で、codec plugin の所有者と利用者を分けてもよい。

推奨方針:

- `HakoniwaCodecRegistry` の所有者が plugin load を担当する
- 利用者 Node は registry 参照を受け取って `decode / encode` を使う

## 起動時の組み込みモデル

もっとも自然な組み込み場所は `_ready()` である。

典型構成:

- manager Node が `HakoniwaCodecRegistry` と `HakoniwaPduEndpoint` を子に持つ
- manager Node の `_ready()` で codec plugin をロードする
- その後に endpoint を `open / start` する

例:

```gdscript
extends Node

@onready var codecs: HakoniwaCodecRegistry = $HakoniwaCodecRegistry
@onready var endpoint: HakoniwaPduEndpoint = $HakoniwaPduEndpoint

func _ready() -> void:
	codecs.load_configured_plugins()
	endpoint.open("res://config/endpoint.json")
	endpoint.start()
```

## 将来の拡張

将来的に signal ベースの convenience API を追加する可能性はある。

ただし、それは pull 型 API の上に載る補助機能として扱う。
