# hakoniwa-core-pro Design

## 目的

`hakoniwa-core-pro` は、Godot を箱庭の時間同期付きアセットとして動作させるための層です。

`hakoniwa-pdu-endpoint` が担当していたのは主に「状態の送受信」でした。  
`hakoniwa-core-pro` ではこれに加えて、

- シミュレーション開始 / 停止 / リセット
- 箱庭ワールド時間との同期
- Godot 側のフレーム更新タイミング制御

を扱います。

このドキュメントは、Godot 統合における `hakoniwa-core-pro` の初期設計方針を固定するためのものです。

## 前提理解

`hakoniwa-core-pro` の構成要素は大きく以下です。

- `hako-master`
  シミュレーション全体の時刻管理と同期を担う
- `hako-conductor`
  シミュレーションの開始、停止、ステップ進行を制御する
- asset API
  個々のアセットが開始 / 停止 / リセットや時刻通知を受け取る

Godot 統合で重要なのは、Godot 自身がこのうちどの役割を持つかです。

## 初期方針

初期フェーズでは、Godot は **polling asset** として参加させる。

つまり、

- Godot は `conductor` にはしない
- Godot は `master` も持たない
- 外部で動作する conductor が時間を進める
- Godot は polling API でイベントを受け取り、自分の処理を進める

という構成を基本とする。

この方針にする理由は以下です。

- Godot の main loop と `hakoniwa-core-pro` の callback loop を直接混ぜないため
- `_process()` / `_physics_process()` から明示的に制御できるため
- 外部 conductor が複数アセットの時間責務を一元管理できるため
- 今の `HakoniwaEndpointNode` の poll ベース設計と整合するため

加えて、Godot 側は **single-asset model** を前提にする。

つまり、

- 1 Godot process = 1 Hakoniwa asset
- `hakoniwa-core-pro` 統合 node はアプリ内に 1 個だけ
- 同一アプリ内で複数 `HakoniwaSimulationNode` を同時に持つことは想定しない

一方で、PDU endpoint は別責務なので複数 instance を許可する。

## 採用する API 面

Godot 統合の初期実装では、callback API ではなく polling C API を使う。

主に使う API は以下。

- `hakoniwa_asset_init()`
- `hakoniwa_asset_register_polling(name)`
- `hakoniwa_asset_get_event(name)`
- `hakoniwa_asset_notify_simtime(name, simtime)`
- `hakoniwa_asset_get_worldtime()`
- `hakoniwa_simevent_get_state()`
- `hakoniwa_simevent_start()`
- `hakoniwa_simevent_stop()`
- `hakoniwa_simevent_reset()`

補助的に、ローカル検証や将来拡張では以下も使う可能性がある。

- `hakoniwa_master_init()`
- `hakoniwa_master_execute()`
- `hakoniwa_master_set_config_simtime(max_delay, delta)`
- `hako_conductor_start(delta_usec, max_delay_usec)`
- `hako_conductor_stop()`

初期デフォルト値:

- conductor `delta_usec (ΔTc)` = `10000` usec
- conductor `max_delay_usec` = `20000` usec
- Godot asset `delta_time_usec (ΔT)` = `20000` usec

ただし、これらは初期フェーズの Godot runtime には直接露出しない。

## Godot 側の責務分離

時間同期を導入しても、既存の endpoint / codec 層の責務は変えない。

### 1. Time Sync Layer

`hakoniwa-core-pro` をラップし、Godot を時間同期付き asset として登録する層。

責務:

- asset 初期化
- polling asset 登録
- start / stop / reset イベント取得
- ワールド時間の取得
- asset 内部時間の通知
- シミュレーション状態の管理

### 2. Endpoint Layer

既存の `HakoniwaEndpointNode` / `HakoniwaTypedEndpoint` が担当する層。

責務:

- PDU endpoint の open / start / stop
- raw / decoded / typed object の送受信

### 3. Integration Layer

Godot の利用者コードまたは上位 wrapper が、Time Sync Layer と Endpoint Layer を接続する層。

責務:

- simulation step ごとに endpoint を pump する
- world time に応じた scene 更新
- stop / reset 時の state cleanup

## 想定する公開クラス

初期実装では、以下の 2 層を提供する前提で設計する。

### Native class

`HakoniwaCoreAsset`

責務:

- polling asset API の native wrapper
- event の数値取得
- world time / current simtime / current sim state の取得
- feedback / notify の実行

### GDScript wrapper

`HakoniwaSimNode`

責務:

- `HakoniwaCoreAsset` の所有
- Node lifecycle との統合
- オプションで SHM endpoint を内包する
- `_physics_process()` からの poll
- start / stop / reset callback の実行

制約:

- 1 Godot application 内で 1 instance のみを許可する
- 2 個目以降の初期化はエラー扱いにする

公開 API の初期案:

- `initialize() -> int`
- `request_start() -> int`
- `request_stop() -> int`
- `request_reset() -> int`
- `tick() -> bool`
- `get_state() -> int`
- `get_world_time_usec() -> int`
- `get_simtime_usec() -> int`
- `set_callbacks(callbacks: HakoniwaSimulationCallbacks) -> void`
- `shutdown() -> void`

設定項目の初期案:

- `asset_name: String`
- `use_internal_shm_endpoint: bool`
- `shm_endpoint_config_path: String`
- `auto_tick_on_physics_process: bool`

## Event モデル

`hakoniwa-core-pro` の asset event は以下を基本に扱う。

- `HakoSimAssetEvent_None`
- `HakoSimAssetEvent_Start`
- `HakoSimAssetEvent_Stop`
- `HakoSimAssetEvent_Reset`
- `HakoSimAssetEvent_Error`

Godot 側では、これを `HakoniwaSimulationCallbacks` の callback 実行へ変換する。

方針:

- `None` は何もしない
- `Start` で endpoint や scene 側の running 状態を有効化する
- `Stop` でシミュレーション更新を停止する
- `Reset` で scene / endpoint の状態を初期化する
- `Error` は `last_error` で利用者へ通知する

## Godot Loop との接続

Godot では callback を直接 asset API に渡さず、main loop で polling する。

### `_ready()`

- `initialize()` を呼ぶ
- `initialize()` の内部で `hakoniwa-core-pro` の asset 初期化と polling asset 登録を行う
- `use_internal_shm_endpoint == true` の場合は内部 SHM endpoint を準備する

### `_physics_process()`

- `tick()` を呼ぶ
- `tick()` の内部で event check と callback を行う
- `tick() == true` のフレームだけユーザが simulation step を進める
- 内部 SHM endpoint が有効なら必要な pump を行う

### `_exit_tree()`

- 内部 SHM endpoint があれば停止
- asset unregister

初期設計では、時間同期の主ループは `_physics_process()` に置く。

理由:

- 固定ステップ更新と相性がよい
- 状態更新と物理更新を一か所にまとめやすい
- `queue` モードの PDU 受信とも整合しやすい

## 利用イメージ

```gdscript
extends Node

@onready var sim: HakoniwaSimNode = $HakoniwaSim

func _ready() -> void:
    sim.asset_name = "GodotAsset"
    sim.use_internal_shm_endpoint = true
    sim.shm_endpoint_config_path = "res://config/endpoint_shm.json"
    sim.initialize()

func _physics_process(_delta: float) -> void:
    if not sim.tick():
        return
    _run_simulation_step()
```

設計上の本体は `tick() -> bool` である。

`request_start()` / `request_stop()` / `request_reset()` は UI や debug から箱庭 lifecycle を要求するための API とする。  
ただし、実際の callback 実行と feedback 完了は次の `tick()` で処理する。

## endpoint との関係

`hakoniwa-core-pro` と `hakoniwa-pdu-endpoint` は役割が違う。

- `hakoniwa-core-pro`
  シミュレーション時刻と asset lifecycle を扱う
- `hakoniwa-pdu-endpoint`
  PDU データの transport と decode を扱う

初期統合では、`HakoniwaSimNode` が `HakoniwaCoreAsset` を必須で持ち、必要な場合だけ SHM endpoint を内包する形を採る。

期待する接続順は以下。

1. `HakoniwaSimNode.initialize()` が asset を register する
2. `use_internal_shm_endpoint == true` なら SHM endpoint を内部準備する
3. `Start` event を受けたら callback を実行し、必要なら内部 SHM endpoint を開始する
4. 各 simulation step で `tick() == true` のフレームだけユーザが処理を進める
5. `Stop` / `Reset` event で callback を実行し、必要なら内部 SHM endpoint と scene state を整理する

このとき、

- `HakoniwaSimNode` は 1 個
- SHM endpoint は `HakoniwaSimNode` の内部オプション
- WebSocket など他 transport の endpoint は独立利用

という構成を前提にする。

SHM endpoint を使う場合の追加ルール:

- `Start` callback で publish 側 PDU の初期値を書き込むこと
- start 直後に peer が読んでも成立する状態を作ってから `start_feedback_ok()` を返すこと

## スコープ内

初期 `hakoniwa-core-pro` 統合で対象にするもの:

- polling asset としての Godot 参加
- world time の取得
- start / stop / reset event の取得
- Godot loop との統合
- endpoint との最小接続
- 最小 sample の動作確認

## テスト方針

最初のテストは `SimNode + CorePro` のみを対象にする。

つまり、

- Godot 側は single asset として register する
- バックグラウンドで conductor を起動する
- PDU / SHM はまだ使わない
- `request_start()` / `request_stop()` / `request_reset()` と `tick()` の挙動を確認する

確認項目:

- `initialize()` が成功する
- start callback が呼ばれる
- `tick() == true` のフレームが発生する
- `get_simtime_usec()` が進む
- stop / reset callback が呼ばれる

その後の第2段階で、internal SHM endpoint を含む構成へ広げる。

## スコープ外

初期フェーズでは以下は対象外とする。

- Godot が conductor / master を内包する実行形態
- editor plugin としての時間同期 UI
- 複数 asset を 1 Godot process 内で完全管理すること
- `hakoniwa-pdu-rpc` との同時統合
- callback API ベースの asset 実装

## 今後の拡張

将来的には以下を検討する。

- Godot 内蔵 conductor によるローカル単体実行
- time sync と RPC をまとめた高水準 simulation node
- editor からの start / stop / reset 支援
- world time と scene time の差分監視
- time sync policy の切り替え
  - strict sync
  - best effort
  - local preview
