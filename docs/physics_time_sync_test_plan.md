# Physics Time Sync Test Plan

## 目的

`HakoniwaSimNode` の physics time sync 実装について、何をどう確認するかを整理する。

この文書では、完璧な網羅ではなく、初期実装として必要十分な確認観点を定める。

## 対象

対象機能:

- `HakoniwaSimNode` の自律動作
- `simulation_step` signal
- physics 連携なしモード
- physics 連携ありモード
- `BLOCKED_BY_WORLD_TIME` 時の停止 / 再開
- UI 非ブロック要件

## 前提

- `HakoniwaSimNode` は利用者が `tick()` を呼ばなくても動作する
- `simulation_step` は simtime が実際に進んだ時のみ emit する
- `enable_physics_time_sync == false` では `simulation_step` が主実行点
- `enable_physics_time_sync == true` では physics 連携と `simulation_step` の両方を使える
- 初期停止 backend は `SceneTree.paused`

## テスト観点

### 1. 基本起動

確認したいこと:

- `HakoniwaSimNode` をシーンに配置し、`initialize()` できる
- start / stop / reset lifecycle が壊れていない
- `simulation_started` / `simulation_stopped` / `simulation_reset` が発火する

### 2. non-physics モード

設定:

- `enable_physics_time_sync = false`

確認したいこと:

- 利用者が `tick()` を呼ばなくても simtime が進む
- `simulation_step` が発火する
- `simulation_step` の引数として `simtime_usec` / `world_time_usec` が取れる
- `simulation_step` は simtime が進まないフレームでは発火しない

### 3. physics 同期モード

設定:

- `enable_physics_time_sync = true`

確認したいこと:

- world time に追いつける間は physics step が進む
- `simulation_step` も発火する
- `auto_sync_delta_time_with_physics == true` の場合、`delta_time_usec` が physics `ΔT` 由来の値になる
- world time 不足時に `BLOCKED_BY_WORLD_TIME` へ遷移する
- world time が追いついたら再開できる

### 4. UI 非ブロック

設定:

- physics 同期モード
- UI root または monitor node に `process_mode = Always`

確認したいこと:

- blocked 中でも UI が固まらない
- monitor 相当の `_process()` が継続する
- 再開操作または再開条件判定が継続できる

### 5. internal SHM endpoint 連携

設定:

- `use_internal_shm_endpoint = true`

確認したいこと:

- start / stop / reset に追従して endpoint lifecycle が壊れない
- running 中は recv dispatch が行われる
- blocked 中は recv event を積極発火しない

## 実施レベル

初期段階では、次の 3 レベルで確認する。

1. 既存 example の再確認
2. 最小手動シーンでの確認
3. 必要なら headless smoke への反映

基本方針として、まずは既存 example を最大限に利用する。

- `enable_physics_time_sync = false`
- `enable_physics_time_sync = true`

を切り替えて同じ example を使い、挙動差を確認する。

特に重要なのは、

1. `false` のとき既存挙動を壊していないこと
2. `true` のとき期待した停止 / 再開ルートを通っていること

である。

## 手順

### 事前準備

ビルド:

```bash
cmake --preset default
cmake --build --preset default
```

Godot 実行ファイルの例:

```bash
/Applications/Godot_mono.app/Contents/MacOS/Godot
```

以降のコマンドでは、この実行ファイルを `GODOT` と表記する。

`core_pro_smoke` は conductor 前提なので、単独の `GODOT --headless --path ...` ではなく runner を使う。

runner:

```bash
bash tools/run_core_pro_smoke.sh
```

physics 同期フラグ切り替え:

```bash
HAKO_ENABLE_PHYSICS_TIME_SYNC=0 bash tools/run_core_pro_smoke.sh
HAKO_ENABLE_PHYSICS_TIME_SYNC=1 bash tools/run_core_pro_smoke.sh
```

debug log と観測ステップ数:

```bash
HAKO_ENABLE_PHYSICS_TIME_SYNC=1 \
HAKO_DEBUG_TIME_SYNC_LOGS=1 \
HAKO_SMOKE_STEP_TARGET=20 \
bash tools/run_core_pro_smoke.sh
```

### 手順 A: 既存 `core_pro_smoke`

対象:

- [examples/core_pro_smoke/main.gd](/Users/tmori/project/oss/hakoniwa-godot/examples/core_pro_smoke/main.gd:1)

目的:

- non-physics モードで `simulation_step` 主導の lifecycle が成立すること
- physics 同期フラグを切り替えて挙動差を確認できること

実行コマンド:

```bash
bash tools/run_core_pro_smoke.sh
```

GUI で確認する場合:

```bash
GODOT --path examples/core_pro_smoke
```

確認項目:

#### A-1. `enable_physics_time_sync = false`

- 起動できる
- start callback が入る
- `simulation_step` により step ログが進む
- stop -> reset -> restart の一連が成立する
- 既存期待ログが維持される

ここは回帰確認として重要である。

#### A-2. `enable_physics_time_sync = true`

- 起動できる
- physics 同期ルートでも lifecycle が破綻しない
- blocked に入る場合は debug log で確認できる
- 再開時のルートも debug log で確認できる

切り替え方法:

- 環境変数 `HAKO_ENABLE_PHYSICS_TIME_SYNC=1` を付けて実行する

期待ログ:

- `HAKO_CORE_SMOKE_START_FEEDBACK_OK`
- `HAKO_CORE_SMOKE_STOP_FEEDBACK_OK`
- `HAKO_CORE_SMOKE_RESET_FEEDBACK_OK`
- `HAKO_CORE_SMOKE_OK`

追加 debug log 候補:

- `SYNC_STATE_RUNNING`
- `SYNC_STATE_BLOCKED_BY_WORLD_TIME`
- `PHYSICS_BACKEND_PAUSED`
- `PHYSICS_BACKEND_RESUMED`

blocked 経路を観測したい場合は、`HAKO_SMOKE_STEP_TARGET` を増やして観測時間を伸ばす。

### 手順 B: 既存 `core_pro_two_asset`

対象:

- [examples/core_pro_two_asset/main.gd](/Users/tmori/project/oss/hakoniwa-godot/examples/core_pro_two_asset/main.gd:1)

目的:

- non-physics モードで internal SHM endpoint と `simulation_step` が両立すること
- 同じ example で physics 同期フラグを切り替えて確認できること

実行コマンド:

```bash
# 端末1
bash tools/run_core_pro_conductor.sh

# 端末2
cd /Users/tmori/project/oss/hakoniwa-godot/examples/core_pro_two_asset
python python_controller.py config/comm/pdu_def.json

# 端末3
/Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path /Users/tmori/project/oss/hakoniwa-godot/examples/core_pro_two_asset
```

補足:

- `core_pro_two_asset` は起動順依存がある
- 現時点で確認できている安定手順は `conductor -> controller -> Godot`
- Python controller には `config/comm/pdu_def.json` を渡す
- `endpoint_shm_with_pdu.json` は Godot endpoint 用であり、Python controller には渡さない
- `bash tools/run_core_pro_conductor.sh` と `bash tools/run_core_pro_two_asset_controller.sh` は単独起動補助として使える

physics 同期フラグ切り替え:

```bash
# 端末3 の Godot 起動だけを切り替える
HAKO_ENABLE_PHYSICS_TIME_SYNC=0 /Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path /Users/tmori/project/oss/hakoniwa-godot/examples/core_pro_two_asset
HAKO_ENABLE_PHYSICS_TIME_SYNC=1 /Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path /Users/tmori/project/oss/hakoniwa-godot/examples/core_pro_two_asset
```

GUI で確認する場合:

```bash
/Applications/Godot_mono.app/Contents/MacOS/Godot --path /Users/tmori/project/oss/hakoniwa-godot/examples/core_pro_two_asset
```

補足:

- `core_pro_two_asset` は conductor に加えて Python controller が必要
- 2026-04-16 時点では、3 端末で順に起動する手順のみを安定手順とする

確認項目:

#### B-1. `enable_physics_time_sync = false`

- typed endpoint が bind できる
- `simulation_step` ごとに pos が送信される
- motor subscription が受信できる
- 所定 step 数で完走する

ここが「普通に動く」ことが重要である。

#### B-2. `enable_physics_time_sync = true`

- 起動できる
- physics 同期ルートでも endpoint lifecycle が壊れない
- blocked 中は recv event を出していないことを debug log で確認できる
- 再開後に step が再び進むことを確認できる

切り替え方法:

- 環境変数 `HAKO_ENABLE_PHYSICS_TIME_SYNC=1` を付けて実行する

期待ログ:

- `HAKO_TWO_ASSET_START_FEEDBACK_OK`
- `HAKO_TWO_ASSET_RECV_MOTOR:...`
- `HAKO_TWO_ASSET_STEP:...`
- `HAKO_TWO_ASSET_OK`

### 手順 C: physics 同期モードの最小シーン

対象:

- 新規の最小確認シーンを作成するか、既存 example を一時的に流用する

設定:

- `enable_physics_time_sync = true`
- `delta_time_usec` を physics `ΔT` と一致させる

実行コマンド:

```bash
GODOT --path <physics-sync-test-project>
```

目的:

- 既存 example だけでは見えにくい pause/backend の基本成立性確認

確認項目:

1. running 中は `simulation_step` が発火する
2. world time 不足で blocked へ遷移する
3. blocked 中に `is_blocked_by_world_time()` が true になる
4. blocked 中でも `Always` node の `_process()` が継続する
5. world time が追いついたら再開する
6. `get_configured_delta_time_usec()` が期待値を返す

確認の目安:

- Godot デフォルト設定なら `16667` usec

### 手順 D: UI 非ブロック確認

対象:

- physics 同期モードの最小シーン

構成:

- `HakoniwaSimNode`
- `process_mode = Always` の UI / monitor node
- blocked 状態を可視化するラベルやログ

実行コマンド:

```bash
GODOT --path <physics-sync-ui-test-project>
```

確認項目:

- blocked 中に UI 表示更新が止まらない
- blocked 中でもボタンや簡易操作が反応する
- pause backend により simulation だけが止まっている

## 期待する判定基準

### Pass

- 既存 examples が `tick()` 呼び出しなしで成立する
- `enable_physics_time_sync = false` で既存相当挙動を維持する
- `enable_physics_time_sync = true` で期待した停止 / 再開ルートを通ることを debug log で確認できる
- `simulation_step` が意図通り発火する
- physics 同期モードで停止 / 再開が確認できる
- blocked 中も UI が止まらない

### Known Limitations

初期段階では、次を limitation として許容する。

- 停止 backend は `SceneTree.paused` のみ
- physics 同期モードの確認は最小ケースまで
- transport 全種の組み合わせ確認は未実施
- 高負荷時や長時間実行時の評価は未実施

## 実施後に更新する文書

- [docs/physics_time_sync_strategy.md](/Users/tmori/project/oss/hakoniwa-godot/docs/physics_time_sync_strategy.md:1)
- [docs/physics_time_sync_impl.md](/Users/tmori/project/oss/hakoniwa-godot/docs/physics_time_sync_impl.md:1)
- [docs/api_reference.md](/Users/tmori/project/oss/hakoniwa-godot/docs/api_reference.md:1)
- `README.md`

## メモ

この段階のテストは、「実装の方向性が成立するか」を見るものである。

初期確認では、細かなタイミング精度よりも次を優先する。

- `false` で従来挙動を壊していないか
- `true` で期待した制御ルートを通っているか

後者は debug log を積極的に利用して確認する。

debug log を入れる候補:

- `initialize()` 時の `delta_time_usec`
- `SYNC_STATE_RUNNING`
- `SYNC_STATE_BLOCKED_BY_WORLD_TIME`
- pause backend の停止 / 再開
- `simulation_step(simtime, world_time)` 発火点

問題が見つかった場合は、

- 失敗条件
- 再現手順
- 期待していた挙動
- 実際の挙動

を残し、設計と実装のどちらの論点かを切り分ける。
