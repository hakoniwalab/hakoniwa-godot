# Physics Time Sync Implementation

## 目的

[physics_time_sync_strategy.md](physics_time_sync_strategy.md) で定めた方針を、`HakoniwaSimNode` の実装へ落とす。

この文書は、初期実装のための実装設計メモである。

## スコープ

この段階で扱うのは次に限定する。

- `HakoniwaSimNode` の内部 state model
- `_physics_process()` と `_process()` の責務分割
- physics 停止 / 再開の基本方式
- UI 非ブロック要件の反映
- ユーザ公開面の最小モデル
- 最低限の検証方針

この段階ではまだ扱わない。

- 複数停止方式の抽象化
- 高度な自動同期
- 汎用 editor support
- 完全な backward compatibility 設計

## 前提

採用前提:

1. asset time の進行点は `_physics_process()`
2. physics 連携は opt-in
3. world time に追いつけない間は simulation step を止める
4. 停止中の監視と再開判定は `_process()`
5. UI は止めない
6. UI root / monitor node は `process_mode = Always` を前提にする

加えて、`HakoniwaSimNode` は利用者から見て「配置して設定すれば自律動作する node」として設計する。
そのため、通常利用では利用者に `tick()` を呼ばせない。

## 実装の基本構成

`HakoniwaSimNode` は次の 3 層責務を持つ。

### 1. Hakoniwa lifecycle 層

- asset initialize / unregister
- start / stop / reset event 処理
- feedback / notify 実行
- world time / simtime / simulation state の管理

### 2. physics time sync 層

- `_physics_process()` で asset time を進める
- world time に対して step 実行可否を判定する
- world time 不足時に physics 停止状態へ遷移する
- 再開可能時に physics 実行状態へ戻す

### 3. monitor / UI safety 層

- `_process()` で停止中の監視を行う
- UI 非ブロックを維持する
- 必要なら pause / active 制御を切り替える

### 4. user runtime interface 層

- inspector 設定だけで動作を開始できる
- 利用者が `_physics_process()` から `tick()` を呼ばなくてよい
- 必要なら Hakoniwa step に同期した callback / signal を提供する

## 状態モデル

初期実装では、少なくとも以下の内部状態を持つ。

```text
UNINITIALIZED
STOPPED
RUNNABLE
RUNNING
BLOCKED_BY_WORLD_TIME
STOPPING
RESETTING
ERROR
TERMINATED
```

### 状態の意味

- `UNINITIALIZED`
  - `initialize()` 前
- `STOPPED`
  - asset は存在するが simulation は停止中
- `RUNNABLE`
  - start 待ち、または start 可能
- `RUNNING`
  - `_physics_process()` で step を進められる状態
- `BLOCKED_BY_WORLD_TIME`
  - simulation state 自体は running だが、`next_simtime > world_time` のため step 不可
- `STOPPING`
  - stop event 処理中
- `RESETTING`
  - reset event 処理中
- `ERROR`
  - エラーにより進行不可
- `TERMINATED`
  - unregister / 終了済み

### `BLOCKED_BY_WORLD_TIME` の位置付け

この状態は重要である。

これは stop とは異なり、

- physics step は止める
- UI は止めない
- `_process()` による再開監視は続ける

という性質を持つ。

## ループ責務

### `_physics_process(delta)`

主責務:

- asset time の進行判定
- step 実行
- internal SHM endpoint の tick 連携
- `RUNNING` / `BLOCKED_BY_WORLD_TIME` の遷移

処理イメージ:

1. lifecycle event を確認する
2. running でなければ必要な状態遷移だけ行って return
3. `next_simtime = current_simtime + delta_time_usec`
4. `world_time` を取得する
5. `next_simtime <= world_time` なら step 実行
6. そうでなければ `BLOCKED_BY_WORLD_TIME` へ遷移

### `_process(delta)`

主責務:

- 停止中の再開監視
- UI 非ブロック前提の監視ループ
- state に応じた physics 再開トリガ

処理イメージ:

1. `BLOCKED_BY_WORLD_TIME` 以外なら何もしない
2. `world_time` を再取得する
3. `next_simtime <= world_time` なら `RUNNING` へ戻す
4. 必要なら physics 再開処理を呼ぶ

重要なのは、`_process()` は通常時の simulation step を持たないこと。

## ユーザ公開モデル

### 基本方針

`HakoniwaSimNode` は「置いて設定すれば動く」runtime node とする。

利用者の基本導線:

1. シーンに `HakoniwaSimNode` を配置する
2. inspector で `asset_name` や physics 連携設定を行う
3. 必要なら signal / callback を接続する
4. あとは node 自身が時刻同期、停止、再開、endpoint 連携を内部で処理する

### `tick()` の扱い

初期実装では `tick()` を公開 API として残すことはできるが、通常利用では推奨しない。

設計方針:

- 通常利用では `tick()` を利用者に呼ばせない
- `HakoniwaSimNode` 自身が `_physics_process()` / `_process()` の中で内部利用する
- 将来的には `tick()` を internal / advanced API 相当に縮退させることを検討する

つまり `tick()` は主入口ではなく、実装詳細へ寄せる。

## 時刻管理

### 正本

physics 連携有効時の asset time の正本は `_physics_process()` 側とする。

### `delta_time_usec`

初期方針:

- physics 連携有効時は Godot physics `ΔT` に合わせる
- 具体的には `physics_ticks_per_second` または `delta` から求める
- 手動設定がある場合も、初期実装では一致しないなら warning または error を検討する

初期実装では、次の設定を持つ。

- `auto_sync_delta_time_with_physics: bool`

挙動:

- `enable_physics_time_sync == true`
- かつ `auto_sync_delta_time_with_physics == true`

の場合、`initialize()` 時に `Engine.physics_ticks_per_second` から `delta_time_usec` を自動設定する。

計算式:

```text
round(1_000_000 / physics_ticks_per_second)
```

Godot のデフォルト `physics_ticks_per_second` は `60` なので、デフォルトでは `16667 usec` となる。

手動値を維持したい場合は `auto_sync_delta_time_with_physics = false` を使う。

### world time 判定

判定式は単純にする。

```text
next_simtime_usec <= world_time_usec
```

成立時のみ 1 step 実行する。

## physics 停止 / 再開

この文書では停止方式をまだ 1 つに固定しない。

ただし初期実装では、次の抽象責務を `HakoniwaSimNode` に持たせる。

- `enter_physics_blocked_state()`
- `leave_physics_blocked_state()`

これにより、内部実装として

- `SceneTree.paused`
- `PhysicsServer2D/3D.set_active(false)`

のどちらを使うかを後で差し替えやすくする。

初期実装でまず試す対象は 1 つに絞ってよい。

初期実装の第一候補は `SceneTree.paused` とする。

理由:

- Godot 標準機能で扱える
- UI / monitor node を `process_mode = Always` にする方針と整合する
- 初手の実装コストを抑えられる

ただし、`SceneTree.paused` は公開 API や state model に直接露出させず、内部 backend として扱う。
将来的に必要であれば physics server 制御方式へ差し替えられる構造を維持する。

## UI 非ブロック要件

明示要件:

1. simulation 停止で UI を止めない
2. stop / blocked 中も monitor loop は継続する
3. UI root / monitor node は `process_mode = Always` を前提とする

これに合わせて、`HakoniwaSimNode` 自体も monitor 責務を持つ場合は `Always` 相当の扱いを検討する。

## `HakoniwaSimNode` API への反映

初期実装では、既存 API を大きく壊さずに拡張する。

候補:

- `enable_physics_time_sync: bool`
- `monitor_during_block: bool`
- `get_sync_state() -> int`
- `is_blocked_by_world_time() -> bool`
- `auto_initialize_on_ready: bool`
- `auto_start_on_ready: bool`
- `simulation_step` signal

`tick()` については次の扱いを第一候補とする。

1. physics 連携モードでは内部利用 API とする
2. 非 physics モードでは advanced API としてのみ残す
3. docs では主入口として説明しない

## ユーザコード実行点

利用者は「箱庭の時間で動く callback」を欲しがる可能性が高い。

ただし、利用者コードを Hakoniwa 固有 API に強く依存させすぎるのは避けたい。

そのため、初期設計では `simulation_step` signal を共通基盤として持ち、その位置付けを 2 モードで分ける。

候補 signal:

- `simulation_step(simtime_usec, world_time_usec)`

### 1. physics 連携あり

この場合、利用者の simulation code は Godot physics loop に自然に載せられる。

つまり、

- `HakoniwaSimNode` が physics 停止 / 再開を内部で制御する
- 利用者は通常の physics 連携ノードとして扱う
- Hakoniwa step と一致したタイミングで `simulation_step` signal も受け取れる

このモードでは、

- physics world と統合した使い方ができる
- 同時に `simulation_step` signal による callback も使える

つまり両方を許可する。

### 2. physics 連携なし

この場合、Hakoniwa の時刻に同期した利用者コードの実行点が別途必要になる。

この方式なら、

- 利用者は callback 登録で Hakoniwa 時刻同期処理を書ける
- 物理エンジンへ依存しない
- `Hakoniwa` 固有の概念は signal 名と引数に閉じ込められる

初期実装では、

- `enable_physics_time_sync == false` の場合、`simulation_step` signal は MUST
- `enable_physics_time_sync == true` の場合、physics 連携と `simulation_step` signal の両方を使える

とする。

### モード別仕様

#### `enable_physics_time_sync == false`

- `simulation_step` signal は必須のユーザ実行点
- 利用者はこの signal を受けて simulation code を書く
- physics world との同期は framework の責務に含めない

#### `enable_physics_time_sync == true`

- `HakoniwaSimNode` が physics 連携を内部制御する
- 利用者は physics world ベースで利用できる
- 加えて `simulation_step` signal も利用できる
- つまり physics 連携と callback の両方を許可する

## internal SHM endpoint との関係

internal SHM endpoint の dispatch は simulation step と整合する必要がある。

初期方針:

- start / stop / reset event では従来通り lifecycle と合わせる
- running 中の recv dispatch は simulation step の近傍で実行する
- blocked 中に recv dispatch をどう扱うかは明示判断する

初期実装では保守的に、

- blocked 中は recv dispatch を積極的には進めない

を第一候補とする。

## 初期シーケンス

### 通常 running

```text
_physics_process()
  -> event check
  -> world_time 取得
  -> next_simtime 判定
  -> step 実行
  -> simtime 更新
```

### world time 不足

```text
_physics_process()
  -> next_simtime > world_time
  -> BLOCKED_BY_WORLD_TIME へ遷移
  -> physics 停止処理

_process()
  -> world_time を監視
  -> 再開可能になれば RUNNING へ戻す
  -> physics 再開処理
```

### stop / reset

```text
event check
  -> STOP / RESET event
  -> callback 実行
  -> endpoint 整理
  -> feedback
  -> 状態遷移
```

## 最小実装方針

初回実装では、以下まで入れればよい。

1. `HakoniwaSimNode` に内部 sync state を追加する
2. `_physics_process()` を asset time の進行点として使うモードを追加する
3. world time 不足時に `BLOCKED_BY_WORLD_TIME` へ遷移する
4. `_process()` で再開監視する
5. 通常利用では `tick()` を利用者に呼ばせない構成へ寄せる
6. physics 連携なしモード用の step signal を追加する
7. UI / monitor 用 `Always` 要件をドキュメント化する

この段階ではまだ不要:

- 完璧な停止方式比較
- 全 transport との整合
- 全サンプル更新

## 検証項目

最低限確認すること:

1. running 中に `_physics_process()` で simtime が進む
2. world time 不足で blocked へ遷移する
3. blocked 中でも UI / monitor が止まらない
4. world time が追いついたら再開できる
5. start / stop / reset lifecycle が破綻しない

## ドキュメント反映先

実装後は以下を更新対象にする。

- [physics_time_sync_strategy.md](physics_time_sync_strategy.md)
- [../issue-physics.md](../issue-physics.md)
- [../task.md](../task.md)
- `README.md`
- `docs/api_overview.md`
- `docs/api_reference.md`

## 関連

- [physics_time_sync_strategy.md](physics_time_sync_strategy.md)
- [../issue-physics.md](../issue-physics.md)
- `addons/hakoniwa/scripts/hakoniwa_simulation_node.gd`
