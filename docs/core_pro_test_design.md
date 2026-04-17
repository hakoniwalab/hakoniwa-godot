# hakoniwa-core-pro Test Design

## 目的

この文書は、`hakoniwa-core-pro` 統合のテスト方針を固定するためのものです。

特に、Godot 側の時間同期実装は

- conductor が別プロセスで必要
- asset register が必要
- lifecycle event と feedback の順序が重要

という性質を持つため、実装前にテスト実行方式を決めておく必要がある。

## 前提

`hakoniwa-core-pro` の確認は conductor なしでは成立しない。

したがって、Godot 側のテストは以下を前提にする。

- conductor をバックグラウンドで起動する
- Godot は headless で起動する
- Godot 側は single asset として register する
- `tick()` を `_physics_process()` から回す

## テストレベル

初期フェーズではテストを 2 段に分ける。

### 1. CorePro Smoke

対象:

- `HakoniwaCoreAsset`
- `HakoniwaSimNode`

ここでは PDU / SHM をまだ使わない。

確認したいもの:

- asset register が成功する
- `request_start()` が event として反映される
- start callback が 1 回呼ばれ、start feedback が返る
- stop callback が呼ばれ、stop feedback が返る
- reset callback が呼ばれ、reset feedback が返る
- reset 後に再 start できる

### 2. CorePro + SHM Smoke

対象:

- `HakoniwaSimNode`
- internal SHM endpoint

ここでは SHM endpoint を有効化する。

確認したいもの:

- internal SHM endpoint の初期化
- `on_simulation_start()` で初期値 PDU を書ける
- callback 完了後に framework 側が `write_pdu_done` を実行する
- callback 完了後に framework 側が `start_feedback_ok()` を実行する
- step 中に internal SHM endpoint を利用できる

## テスト実行方式

テスト実行は **B. launcher / shell script でまとめて起動** を採用する。

理由:

- conductor の起動・停止をまとめて管理できる
- Godot headless 実行と後片付けを一括化できる
- CI 化しやすい
- 手元再現もしやすい

初期案としては、`tools/` に test runner を置く。

候補:

- `tools/run_core_pro_smoke.sh`
- `tools/run_core_pro_shm_smoke.sh`

既定値:

- conductor `delta_usec (ΔTc)` = `10000` usec
- conductor `max_delay_usec` = `20000` usec
- Godot asset `delta_time_usec (ΔT)` = `20000` usec

初期 skeleton としては以下を置く。

- runner: `tools/run_core_pro_smoke.sh`
- Godot test scene: `tests/smoke/core_pro_smoke/`

## 初期の最小テスト構成

最初に作るべきテストは **single asset + conductor lifecycle smoke** とする。

構成:

- conductor をバックグラウンド起動
- Godot headless で test scene を起動
- `HakoniwaSimNode` だけを使う
- PDU / SHM はまだ使わない

成功条件:

- `initialize()` 成功
- asset register 確認
- start callback 実行
- start feedback 完了
- stop callback 実行
- stop feedback 完了
- reset callback 実行
- reset feedback 完了
- reset 後に再 start して start callback / feedback が再度成立
- 再 start 後に `simtime` が複数 step 進行する

確認済みベースライン:

- conductor `delta_usec (ΔTc)` = `10000` usec
- conductor `max_delay_usec` = `20000` usec
- Godot asset `delta_time_usec (ΔT)` = `20000` usec
- lifecycle:
  - `HAKO_CORE_SMOKE_START_CALLBACK`
  - `HAKO_CORE_SMOKE_START_FEEDBACK_OK`
  - `HAKO_CORE_SMOKE_STOP_CALLBACK`
  - `HAKO_CORE_SMOKE_STOP_FEEDBACK_OK`
  - `HAKO_CORE_SMOKE_RESET_CALLBACK`
  - `HAKO_CORE_SMOKE_RESET_FEEDBACK_OK`
  - `HAKO_CORE_SMOKE_RESTART_CALLBACK`
  - `HAKO_CORE_SMOKE_RESTART_FEEDBACK_OK`
- time step:
  - `HAKO_CORE_SMOKE_STEP:1 simtime=20000 world=20000`
  - `HAKO_CORE_SMOKE_STEP:2 simtime=40000 world=40000`
  - `HAKO_CORE_SMOKE_STEP:3 simtime=60000 world=60000`
  - `HAKO_CORE_SMOKE_OK`

## lifecycle の期待シーケンス

### Start

```text
runner starts conductor
  -> Godot headless starts
  -> SimNode.initialize()
  -> script calls request_start()
  -> next tick:
       poll_event()
       start callback
       start_feedback_ok()
       return false
  -> subsequent tick:
       return true
```

### Stop

```text
script calls request_stop()
  -> next tick:
       poll_event()
       stop callback
       stop_feedback_ok()
       return false
```

### Reset

```text
script calls request_reset()
  -> next tick:
       poll_event()
       reset callback
       reset_feedback_ok()
       return false
```

### Re-Start

```text
script calls request_reset()
  -> next tick:
       poll_event()
       reset callback
       reset_feedback_ok()
       return false

script calls request_start()
  -> next tick:
       poll_event()
       start callback
       start_feedback_ok()
       return false
```

## テストシーンの責務

Godot 側 test scene は以下を担当する。

- `HakoniwaSimNode` の作成
- callback 実装の登録
- `_physics_process()` からの `tick()`
- 所定フレームで `request_start()` / `request_stop()` / `request_reset()` の実行
- ログ出力による成功判定のための markers 出力

## callback テスト用 marker

テストでは log marker を明示的に出す。

例:

- `HAKO_CORE_SMOKE_INITIALIZED`
- `HAKO_CORE_SMOKE_REGISTERED`
- `HAKO_CORE_SMOKE_START_CALLBACK`
- `HAKO_CORE_SMOKE_START_FEEDBACK_OK`
- `HAKO_CORE_SMOKE_STOP_CALLBACK`
- `HAKO_CORE_SMOKE_STOP_FEEDBACK_OK`
- `HAKO_CORE_SMOKE_RESET_CALLBACK`
- `HAKO_CORE_SMOKE_RESET_FEEDBACK_OK`
- `HAKO_CORE_SMOKE_RESTART_CALLBACK`
- `HAKO_CORE_SMOKE_RESTART_FEEDBACK_OK`
- `HAKO_CORE_SMOKE_STEP:1`
- `HAKO_CORE_SMOKE_STEP:2`
- `HAKO_CORE_SMOKE_STEP:3`
- `HAKO_CORE_SMOKE_OK`

runner はこれらの marker を見て成功判定する。

## runner の責務

shell runner は以下を担当する。

- conductor 起動
- 必要な環境変数設定
- Godot headless 実行
- 終了コードと marker の確認
- conductor 停止
- 残プロセス cleanup

## SHM smoke で追加確認すること

第2段階では以下の marker を追加する。

- `HAKO_CORE_SHM_START_WRITE_INITIAL`
- `HAKO_CORE_SHM_WRITE_DONE`
- `HAKO_CORE_SHM_START_FEEDBACK_OK`
- `HAKO_CORE_SHM_TICK_TRUE`
- `HAKO_CORE_SHM_OK`

## 次段の統合テスト

lifecycle smoke が通った後は、**2 アセット構成**へ進む。

構成:

- Asset A: Godot (`HakoniwaSimNode` + internal SHM endpoint)
- Asset B: Python

Python 側の相方は `hakoniwa-core-pro/examples/pdu_communication` の実装方針を参考にする。

この段階で確認すること:

- Godot と Python がそれぞれ asset として register できる
- start / stop / reset が両 asset に伝播する
- SHM PDU の read / write が両方向で成立する
- Godot 側の start callback で初期値 PDU write が有効に機能する

## 実装順

テスト実装は以下の順で進める。

1. runner script の雛形を作る
2. `SimNode + CorePro` の test scene を作る
3. callback marker を確認する
4. feedback marker を確認する
5. reset 後の再 start を確認する
6. SHM smoke を追加する
7. 2 アセット統合テストを追加する

## 初期スコープ外

この段階では以下はまだ対象外とする。

- WebSocket endpoint を含む統合テスト
- 複数 asset を含む分散シミュレーションテスト
- CI 上での長時間 soak test
- performance / latency 測定
