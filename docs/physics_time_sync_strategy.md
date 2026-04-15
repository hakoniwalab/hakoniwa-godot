# Physics Time Sync Strategy

## 目的

`HakoniwaSimNode` の physics 連携設計を、Godot の仕様に基づいて先に固定する。

この文書は、実装前の設計判断メモである。

扱う論点:

- Godot で physics を止めたとき、何が止まり、何が動くか
- UI を止めずに simulation だけ止める方法があるか
- `HakoniwaSimNode` の時刻同期ポイントを `_process()` と `_physics_process()` のどちらに置くべきか
- 採用する設計方針と、その理由

## 結論

現時点の採用方針は以下とする。

1. `HakoniwaSimNode` の asset time の進行点は `_physics_process()` とする
2. Hakoniwa world time に追いつけない場合、simulation step は停止させる
3. 停止中の監視と再開判定は `_process()` 側で行う
4. UI は停止させない
5. UI root と監視ノードは `process_mode = Always` を前提とする
6. physics 連携を使う場合の `delta_time_usec` は Godot の `Time.fixedDeltaTime` 相当に合わせる

要するに、

- 通常時の時刻進行は `_physics_process()`
- 停止時の復帰監視は `_process()`
- UI は `Always`

という分離を採る。

## Godot 仕様の確認

### 1. `SceneTree.paused = true` で physics は止まる

Godot 公式 docs では、`SceneTree.paused = true` にすると次の 2 点が起こる。

- 2D / 3D physics が止まる
- node の process mode に応じて処理が止まる / 続く

参照:

- https://docs.godotengine.org/en/4.4/tutorials/scripting/pausing_games.html

### 2. デフォルトでは `_process()` と `_physics_process()` は止まる

同じ docs では、pause 中に processing を止められた node では以下が呼ばれないと明記されている。

- `_process()`
- `_physics_process()`
- `_input()`
- `_input_event()`

参照:

- https://docs.godotengine.org/en/4.4/tutorials/scripting/pausing_games.html

したがって、pause を使う場合に通常 node をそのまま置くと、監視ループも UI も止まりうる。

### 3. `process_mode = Always` なら pause を無視して処理できる

Godot の `Node.process_mode` には以下がある。

- `Inherit`
- `Pausable`
- `WhenPaused`
- `Always`
- `Disabled`

`Always` は `SceneTree.paused` を無視して processing を継続する。

参照:

- https://docs.godotengine.org/en/4.3/classes/class_node.html
- https://docs.godotengine.org/en/4.4/tutorials/scripting/pausing_games.html

### 4. ノードのデフォルトは `Always` ではない

Godot 4 の docs では、

- 新規 node のデフォルトは `PROCESS_MODE_INHERIT`
- root node のデフォルト相当は `PROCESS_MODE_PAUSABLE`

とされている。

参照:

- https://docs.godotengine.org/en/4.3/classes/class_node.html

つまり、UI や監視ノードを止めたくない場合は、明示的に `Always` を設定する必要がある。

### 5. physics server 自体を active/inactive にできる

Godot docs には、physics server の `set_active()` がある。

- `PhysicsServer2D.set_active(active)`
- `PhysicsServer3D.set_active(active)`

3D docs では「3D physics engine を有効 / 無効化する」と書かれている。
2D docs では `active = false` の場合、「physics step で何もしない」と書かれている。

参照:

- https://docs.godotengine.org/en/stable/classes/class_physicsserver3d.html
- https://docs.godotengine.org/en/4.0/classes/class_physicsserver2d.html

また、pause docs では「pause 中でも physics server は `set_active()` で active にできる」とされている。

参照:

- https://docs.godotengine.org/en/4.4/tutorials/scripting/pausing_games.html

## 仕様から言えること

### 確定して言えること

1. `SceneTree.paused` を使うと physics は止まる
2. デフォルト設定のままでは UI も監視ノードも止まりうる
3. `process_mode = Always` を使えば pause 中でも動かせる node を作れる
4. physics server の active/inactive 制御は API 上可能

### まだ実験が必要なこと

次は実機で確認する。

1. `SceneTree.paused = true` と `process_mode = Always` の組み合わせで、監視ノードの `_process()` が期待通り動くか
2. 同条件で `_physics_process()` はどう止まるか
3. `PhysicsServer2D/3D.set_active(false)` を使った場合、`_process()` / `_physics_process()` がどう振る舞うか
4. どちらの停止方式が `HakoniwaSimNode` に適しているか

## Unity 実装との比較

Unity 側の `hakoniwa-sim-csharp` では以下の構成を採っている。

1. `delta_time_usec` を `Time.fixedDeltaTime` から決める
2. `Physics.simulationMode = SimulationMode.Script` にする
3. `FixedUpdate()` で Hakoniwa step 実行可否を判定する
4. 実行可能なときだけ `Physics.Simulate(Time.fixedDeltaTime)` を呼ぶ

参照:

- [../hakoniwa-sim-csharp/Runtime/sim/HakoAsset.cs](/Users/tmori/project/oss/hakoniwa-sim-csharp/Runtime/sim/HakoAsset.cs:82)
- [../hakoniwa-sim-csharp/Runtime/sim/HakoAsset.cs](/Users/tmori/project/oss/hakoniwa-sim-csharp/Runtime/sim/HakoAsset.cs:93)
- [../hakoniwa-sim-csharp/Runtime/sim/HakoAsset.cs](/Users/tmori/project/oss/hakoniwa-sim-csharp/Runtime/sim/HakoAsset.cs:118)
- [../hakoniwa-sim-csharp/Runtime/sim/core/impl/HakoAssetImpl.cs](/Users/tmori/project/oss/hakoniwa-sim-csharp/Runtime/sim/core/impl/HakoAssetImpl.cs:118)

Godot でも目指す構図は近い。

ただし Godot では、「physics を止めた結果 `_physics_process()` 自体が止まるなら、再開監視を別ループに逃がす必要がある」という点が Unity より強く問題になる。

## 採用する設計方針

### 1. asset time の進行点は `_physics_process()`

理由:

- physics world に結びついた asset の simulation time を、physics step と同じ場所で進められる
- `1 physics tick = 1 Hakoniwa step` という対応を取りやすい
- `delta_time_usec` を Godot physics の `ΔT` に合わせる設計と整合する

### 2. 停止中のみ `_process()` を監視ループに使う

理由:

- physics 停止時に `_physics_process()` が止まる可能性がある
- その場合も Hakoniwa world time の進行監視と再開判定は必要
- UI を止めないためにも、simulation 停止と監視停止を分離する必要がある

したがって、`_process()` は通常時の主ループではなく、停止時の recovery loop と位置付ける。

### 3. UI は絶対にブロックしない

設計要件:

- Hakoniwa world time 待ちで UI を止めない
- simulation が止まっていても、UI 表示と再開操作は可能である
- そのため、UI root と monitor node は `process_mode = Always` を前提にする

### 4. `delta_time_usec` は physics 連携時に Godot 側 `ΔT` に合わせる

physics 連携を有効にする場合、

- `delta_time_usec`
- `Time.fixedDeltaTime`

は一致させる前提とする。

少なくとも初期実装では、

- `1 physics tick = 1 Hakoniwa step`

を基本モデルとする。

## 想定する状態モデル

この設計では、`HakoniwaSimNode` は state machine を持つ必要がある。

最低限必要な状態:

- `RUNNING`
  - `_physics_process()` で通常 step を進める
- `BLOCKED_BY_WORLD_TIME`
  - world time 不足で step 停止中
  - `_process()` が監視して再開を待つ
- `STOPPED_BY_EVENT`
  - stop event により停止中
- `RESETTING`
  - reset 処理中
- `ERROR`
  - エラー状態

特に `BLOCKED_BY_WORLD_TIME` は、単なる stop と分けて扱う必要がある。

理由:

- simulation step は止める
- しかし UI は止めない
- world time の進行監視は続ける

という性質があるため。

## 採用しない方針

### `_physics_process()` だけを主ループにする

採用しない理由:

- 物理停止時に `_physics_process()` 自体が止まると、再開契機を失う可能性がある

### `_process()` を通常時も主ループにする

現時点では第一候補にしない理由:

- asset time の正本を physics と分離すると、physics world と simtime の関係が分かりにくくなる
- `1 physics tick = 1 Hakoniwa step` を維持しづらい

## マニュアルへ反映すべき注意事項

physics 連携を有効にして Godot 側 physics を停止しうる設計を採る場合、利用者向けに次を明記する必要がある。

1. UI はデフォルトでは pause / 停止の影響を受ける可能性がある
2. 停止させたくない UI root は `process_mode = Always` を設定すること
3. 再開監視に使う monitor node も `process_mode = Always` を設定すること
4. simulation 停止と UI 停止は同じものではないこと

## 次の作業

1. `SceneTree.paused` と `PhysicsServer.set_active(false)` の両方で最小検証を行う
2. `_process()` / `_physics_process()` / UI 入力の挙動を確認する
3. その結果で停止方式を 1 つに決める
4. `HakoniwaSimNode` の API と state model を更新する

## 関連

- [issue-physics.md](/Users/tmori/project/oss/hakoniwa-godot/issue-physics.md:1)
- [task.md](/Users/tmori/project/oss/hakoniwa-godot/task.md:1)
- [docs/core_pro_design.md](/Users/tmori/project/oss/hakoniwa-godot/docs/core_pro_design.md)
- [addons/hakoniwa/scripts/hakoniwa_simulation_node.gd](/Users/tmori/project/oss/hakoniwa-godot/addons/hakoniwa/scripts/hakoniwa_simulation_node.gd:1)
