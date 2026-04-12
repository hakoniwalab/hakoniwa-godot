# hakoniwa-core-pro User Interface

## 目的

この文書は、`hakoniwa-core-pro` 統合後に Godot 利用者が **実際に何を書くことになるか** を明確にするためのものです。

設計が正しいかどうかは、内部 API の美しさではなく、

- ユーザが理解できるか
- 実装責務が明確か
- 書かされるコード量が妥当か

で判断する。

## 基本方針

ユーザは以下の 2 つを書く。

1. `HakoniwaSimulationCallbacks` を継承した callback 実装
2. `HakoniwaSimNode` を中心にしたシーン側コード

時間進行そのものは、ユーザが `_physics_process()` から `tick()` を呼ぶことで進める。

つまり、

- 箱庭側がバックグラウンドで勝手に時刻を進めるのではない
- ユーザが Godot の physics loop から同期処理をトリガする
- start / stop / reset は callback 実装側が持つ
- SHM endpoint を使うかどうかは `SimNode` の起動時設定で決める
- WebSocket など他 transport の endpoint は `SimNode` は管理しない
- UI から lifecycle を操作したい場合は `request_start()` / `request_stop()` / `request_reset()` を使う

という構成にする。

## ユーザが実装する callback

想定する基底クラス:

```gdscript
class_name HakoniwaSimulationCallbacks
extends RefCounted

func on_simulation_start() -> void:
    push_error("on_simulation_start() must be implemented")

func on_simulation_stop() -> void:
    push_error("on_simulation_stop() must be implemented")

func on_simulation_reset() -> void:
    push_error("on_simulation_reset() must be implemented")
```

利用者はこれを継承して、自分の simulation 処理を書く。

### 最小例

```gdscript
class_name MySimulationCallbacks
extends HakoniwaSimulationCallbacks

var pose_endpoint: HakoniwaTypedEndpoint
var lidar_endpoint: HakoniwaTypedEndpoint

func _init(pose_ep: HakoniwaTypedEndpoint, lidar_ep: HakoniwaTypedEndpoint) -> void:
    pose_endpoint = pose_ep
    lidar_endpoint = lidar_ep

func on_simulation_start() -> void:
    print("simulation started")
    _write_initial_pdus()

func on_simulation_stop() -> void:
    print("simulation stopped")

func on_simulation_reset() -> void:
    print("simulation reset")

func _apply_pose_to_scene(pose: Variant) -> void:
    pass

func _capture_lidar(world_time_usec: int) -> Variant:
    return null

func _write_initial_pdus() -> void:
    pass
```

## ユーザが書くシーン側コード

利用者は通常、scene root 側で

- endpoint の open
- typed endpoint の取得
- callback object の生成
- simulation node への登録
- `_physics_process()` からの `tick()`
- `tick() == true` のときだけ simulation 処理実行

を書く。

### 最小例

```gdscript
extends Node3D

const HakoniwaSimNode = preload("res://addons/hakoniwa/scripts/hakoniwa_simulation_node.gd")
const MySimulationCallbacks = preload("res://scripts/MySimulationCallbacks.gd")

var simulation: HakoniwaSimNode
var callbacks: MySimulationCallbacks

func _ready() -> void:
    simulation = HakoniwaSimNode.new()
    add_child(simulation)
    simulation.asset_name = "GodotAsset"
    simulation.delta_time_usec = 20000
    simulation.use_internal_shm_endpoint = true
    simulation.shm_endpoint_config_path = "res://config/endpoint_shm.json"

    callbacks = MySimulationCallbacks.new(
        simulation.get_typed_endpoint("drone0", "pose"),
        simulation.get_typed_endpoint("drone0", "scan")
    )

    simulation.set_callbacks(callbacks)
    simulation.initialize()

func _on_start_button_pressed() -> void:
    simulation.request_start()

func _on_stop_button_pressed() -> void:
    simulation.request_stop()

func _on_reset_button_pressed() -> void:
    simulation.request_reset()

func _physics_process(_delta: float) -> void:
    if not simulation.tick():
        return

    var pose = simulation.get_typed_endpoint("drone0", "pose").recv()
    if pose != null:
        _apply_pose(pose)

    var lidar = _capture_lidar()
    if lidar != null:
        simulation.get_typed_endpoint("drone0", "scan").send(lidar)

func _exit_tree() -> void:
    simulation.shutdown()

func _apply_pose(pose: Variant) -> void:
    pass

func _capture_lidar() -> Variant:
    return null
```

## ユーザに要求する実装責務

この設計で、利用者に要求するものは以下。

### 必須

- `HakoniwaSimulationCallbacks` の 3 メソッド実装
- `_physics_process()` から `simulation.tick()` を呼ぶこと
- `tick() == true` のときだけ simulation 処理を書くこと
- `asset_name` を設定すること
- `delta_time_usec` を設定すること
- SHM endpoint を使うなら `use_internal_shm_endpoint` と `shm_endpoint_config_path` を設定すること

既定値:

- conductor `delta_usec (ΔTc)` = `10000` usec
- conductor `max_delay_usec` = `20000` usec
- Godot asset `delta_time_usec (ΔT)` = `20000` usec

SHM endpoint を使う場合の追加必須事項:

- `on_simulation_start()` で初期値 PDU を必ず書くこと
- 相手 asset が最初の step で読む値を start 時点で確定させること
- codec plugin path は `res://addons/hakoniwa/codecs/<package>_codec` の形を使うこと

### 任意

- `_process()` での UI / camera update
- start / stop / reset 時の scene 制御
- UI ボタンからの `request_start()` / `request_stop()` / `request_reset()`
- `get_state()` を使った UI / debug 表示
- `get_simtime_usec()` を使った simtime 表示

## 利用者が書かなくてよいもの

以下は framework 側で持つ。

- `hakoniwa-core-pro` の native C API 呼び出し
- `poll_event()` と feedback の順序制御
- `notify_simtime()` の実行
- event と simulation state の内部管理
- 内部 SHM endpoint の open / start / stop / close
- codec plugin の shared library 解決
- codec plugin に対応する `.gdextension` の初期化

## codec plugin の扱い

`HakoniwaSimNode` と `HakoniwaEndpointNode` を使う通常利用では、codec plugin の GDExtension 初期化順を利用者が意識する必要はない。

一方で、`HakoniwaCodecRegistry` を直接使う low-level 利用では別である。

- 標準 API:
  - `HakoniwaSimNode`
  - `HakoniwaEndpointNode`
- low-level API:
  - `HakoniwaCodecRegistry`

low-level API を直接使う場合は、対応する `<package>_codec.gdextension` を先に `load()` してから plugin を有効化すること。

## 処理シーケンス

### 1. 起動

```text
_ready
  -> simulation.initialize()
      -> asset init
      -> register_polling_asset
      -> use_internal_shm_endpoint == true なら SHM endpoint を初期化
  -> simulation.get_typed_endpoint(...)
  -> callbacks を生成
  -> simulation.set_callbacks(callbacks)

UI から開始したい場合:

```text
button pressed
  -> simulation.request_start()
```
```

### 2. Start

```text
tick
  -> poll_event()
  -> Start event
  -> callbacks.on_simulation_start()
      -> SHM endpoint を使う場合は初期値 PDU を書く
  -> use_internal_shm_endpoint == true なら SHM endpoint start
  -> start_feedback_ok()
  -> return false
```

`request_start()` は Start event の発行要求だけを行う。  
callback 実行と feedback は次の `tick()` で処理する。

### Start callback の注意

SHM endpoint を使う場合、`on_simulation_start()` は単なる通知ではない。

このタイミングで少なくとも以下を行う必要がある。

- publish 側 PDU の初期値設定
- 必要なら 1 回目の write
- 受信側が最初に参照してよい状態への整備

理由:

- SHM は peer-to-peer の既存メモリ状態を読むため
- start 直後に相手 asset が読む可能性があるため
- 初期値を書かないと未初期化または前回残存値を読む危険があるため

### 3. Step

```text
_physics_process
  -> simulation.tick()
      -> poll_event()
      -> if event handled: return false
      -> if not running: return false
      -> world_time と next_asset_time を比較
      -> if まだ進めない: return false
      -> return true
  -> use_internal_shm_endpoint == true なら内部 endpoint を利用可能
  -> user simulation step
  -> notify_simtime(next_asset_time)
```

### 4. Stop

```text
tick
  -> poll_event()
  -> Stop event
  -> callbacks.on_simulation_stop()
  -> use_internal_shm_endpoint == true なら SHM endpoint stop
  -> stop_feedback_ok()
  -> return false
```

### 5. Reset

```text
tick
  -> poll_event()
  -> Reset event
  -> callbacks.on_simulation_reset()
  -> use_internal_shm_endpoint == true なら内部 SHM endpoint cleanup
  -> reset_feedback_ok()
  -> return false
```

## `get_state()` の位置づけ

`get_state()` は提供するが、主用途は以下に限定する。

- デバッグ表示
- UI 表示
- ログ出力
- 現在状態の監視

制御には使わない。

特に、`get_state()` を見て `tick()` を呼ばない、という使い方は不可とする。

理由:

- `tick()` の内部で event check が走るため
- `Start` / `Stop` / `Reset` callback と feedback を `tick()` が担うため
- `tick()` を skip すると lifecycle 処理を取りこぼすため

## transport の考え方

`HakoniwaSimNode` は `hakoniwa-core-pro` を必須で持つ。

追加 transport は以下の扱いにする。

- SHM endpoint
  `HakoniwaSimNode` の内部オプションとして利用可能
- WebSocket / TCP / Zenoh / MQTT など
  `HakoniwaSimNode` は管理しない
  必要ならユーザが独立した `HakoniwaEndpointNode` を別途使う

この分離により、

- `asset_name` と SHM endpoint の整合は `SimNode` が内部管理できる
- 他 transport の独立性は壊さない

## 最初のテスト方法

最初のテストでは、PDU や SHM をまだ使わない。

構成:

- バックグラウンドで conductor を起動する
- Godot headless で `HakoniwaSimNode` だけを動かす
- single asset として register する
- `_physics_process()` で `tick()` を回す
- script または UI から `request_start()` / `request_stop()` / `request_reset()` を呼ぶ

最初に見るべき成功条件:

- `initialize()` 成功
- start callback 実行
- `tick() == true` のフレーム発生
- `get_simtime_usec()` の進行
- stop callback 実行
- reset callback 実行

この確認が通った後で、internal SHM endpoint を有効にした構成へ進む。

## `get_simtime_usec()` の位置づけ

`get_simtime_usec()` も提供する。

これは、

- asset が最後に完了した simulation 時刻
- 現在の step 進行状況の表示
- debug / HUD / log への出力

のために使う。

`get_world_time_usec()` と違い、こちらは asset 自身がどこまで追従できているかを見るための値である。

## 設計評価の観点

このインタフェース設計がよいかどうかは、少なくとも以下で判断する。

- callback 実装だけで利用者の責務が見えるか
- `_physics_process()` から `tick()` を呼ぶだけで運用できるか
- start / stop / reset / step の責務分離が明確か
- endpoint と time sync の責務が混ざっていないか

初期フェーズでは、これ以上の抽象化は入れない。

理由:

- まず最小の mental model を固定したい
- Godot 利用者に必要な実装量を見積もれるようにしたい
- Unity 実装の思想を保ちつつ、Godot に自然な形へ落としたい
