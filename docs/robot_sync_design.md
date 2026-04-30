# Robot Sync Design

## 目的

この文書は、Godot 上でロボットモデルを Hakoniwa / ROS 系 PDU に同期するための
**汎用ライブラリ層**をどう設計するかを定義する。

対象は、当面 `examples/mujoco/assets/tb3_reference_sync.gd` のような
機体固有 script を一般化し、

- TB3 以外の robot model へ横展開できること
- body / joint の対応関係をコードから分離できること
- scene 側 script を薄く保てること
- `hakoniwa-mbody-registry` を入口にして機体追加できること

を実現することにある。

## 背景

現在の試作コードでは、

- `HakoniwaSimNode` から internal SHM endpoint を取得する
- `base_link` 系 PDU と `joint_states` 系 PDU を受信する
- Godot scene 内の body / wheel / joint node に値を反映する

という処理が 1 つの script にまとまっている。

この形は TB3 の検証には十分だが、今後 robot model が増えると以下の問題が出る。

- `robot_name`
- `pdu_name`
- NodePath
- joint 名
- 回転軸
- 符号
- 初期姿勢
- 座標系変換

が script に直書きされ、再利用しにくい。

そのため、**共通同期ロジックを addon 化し、機体差分を外部定義へ逃がす** 方針を採る。

ただし利用者に profile JSON を `hakoniwa-godot` 側で手書きさせるのではなく、
`hakoniwa-mbody-registry` を入口にして、Godot 用入力から最終 profile を生成する。

## ゴール

- `addons/hakoniwa_robot_sync` を Godot addon として提供する
- scene 側は controller を 1 つ置いて生成済み profile JSON を指定するだけで使える
- `sensor_msgs/JointState` のような標準 message を共通ロジックで処理できる
- body / joint 配置差分は `hakoniwa-mbody-registry` 側の入力で吸収する
- 座標変換はライブラリ側の定義済み変換ルールとして提供する

## 非ゴール

この文書の対象外:

- URDF parser を本 addon に同梱すること
- 任意式を JSON に埋め込んで実行すること
- editor 上で profile を GUI 編集すること
- inverse kinematics や constraint solver を提供すること

初期フェーズでは、
**外部から届く pose / joint state を scene node へ安全に反映する**
ことだけを扱う。

## 配置方針

想定する構成:

```text
addons/
  hakoniwa_robot_sync/
    plugin.cfg
    scripts/
      robot_sync_controller.gd
      robot_profile_loader.gd
      robot_profile_validator.gd
      transform_converter.gd
      joint_state_mapper.gd
    schemas/
      robot_profile.schema.json

../hakoniwa-mbody-registry/
  bodies/
    <robot>/
      config/
        viewer.recipe.yaml
        godot_sync.yaml
      generated/
        godot/
          robot_sync.profile.json
```

責務は以下のように分ける。

### `robot_sync_controller.gd`

- `HakoniwaSimNode` と `HakoniwaEndpointNode` を使った受信制御
- `process_recv_events()` 実行
- base pose 受信
- joint_states 受信
- profile に基づく scene node 更新

### `robot_profile_loader.gd`

- 生成済み profile JSON の読み込み
- path 解決
- Dictionary 化

### `robot_profile_validator.gd`

- 必須項目検証
- 型検証
- 値域検証

### `transform_converter.gd`

- position の座標変換
- quaternion / euler / basis の座標変換
- ライブラリがサポートする変換ルールの集約

### `joint_state_mapper.gd`

- `JointState.name[]` と `position[]` から lookup table を構築
- profile の `joint_mappings` に従って Node3D に反映
- 軸、符号、offset の適用

## 基本設計

ライブラリは次の 3 層で考える。

### 1. Runtime Layer

Hakoniwa / Godot 接続の共通処理を持つ。

責務:

- `simulation_ready` 後の endpoint 取得
- typed endpoint の取得
- polling receive の進行
- base_link / joint_states の受信順管理
- 受信失敗時のエラー報告

### 2. Generated Profile Layer

`hakoniwa-mbody-registry` が生成した最終 profile JSON を表現する。

責務:

- robot 名
- PDU 名
- scene 内 node path
- joint 名と node の対応
- 変換ルール選択
- 回転軸、符号、offset

### 3. Conversion Layer

受信した値を Godot 座標系 / node transform に落とす。

責務:

- 座標系変換
- basis / position / rotation 反映
- initial transform を基準にした差分回転適用

## 責務分離

責務は次のように切る。

### `hakoniwa-mbody-registry`

ユーザの入口。

責務:

- robot body 定義を保持する
- viewer 用 scene を生成する
- Godot 用 overlay 設定を読む
- `HakoniwaRobotSyncController` が読む最終 profile JSON を生成する

### `hakoniwa-godot`

ライブラリ提供側。

責務:

- `HakoniwaSimNode` / endpoint / codec を提供する
- `addons/hakoniwa_robot_sync` を提供する
- 生成済み profile JSON を読む
- scene node へ runtime 反映する

重要なのは、`hakoniwa-godot` 側では robot 固有設定を書かないこと。
robot 固有入力は `hakoniwa-mbody-registry` 側で完結させる。

## 利用イメージ

scene 側 script は最終的に薄くし、controller 自体は scene に置く `Node` として扱う。

想定:

- scene に `HakoniwaRobotSyncController` node を追加する
- Inspector で `sim_node_path` を設定する
- Inspector で `profile_path` を設定する
- Inspector で `target_root_path` を設定する

`_physics_process()` や `_process()` に個別の joint 反映コードを書かないのが目標である。

## Runtime API の想定

初期案:

```gdscript
class_name HakoniwaRobotSyncController
extends Node

@export var sim_node_path: NodePath
@export_file("*.json") var profile_path: String
@export var target_root_path: NodePath
@export var auto_start_on_ready: bool = true
@export var debug_logs: bool = false

func set_enabled(value: bool) -> void:
    pass

func is_ready() -> bool:
    return false

func get_last_error_text() -> String:
    return ""
```

`setup()` ベースの API よりも、scene 配置と Inspector 設定で完結する設計を優先する。

内部処理の流れ:

1. profile JSON を load / validate する
2. `sim_node_path` と `target_root_path` を resolve する
3. `simulation_ready` を待つ
4. internal endpoint を取得する
5. profile の `robot_name` / `pdu_name` に基づいて typed endpoint を bind する
6. step ごとに `process_recv_events()` を呼ぶ
7. base pose と joint_states を受信する
8. profile に従って scene node を更新する

## Polling 前提

このライブラリは初期段階では **caller-controlled / poll 型**を前提にする。

理由:

- `HakoniwaSimNode` が internal SHM endpoint を main loop から進める設計だから
- Godot の scene tree 更新を main thread に揃えたいから
- transport ごとの差異を減らしたいから

したがって profile 利用時の標準動作は:

- SHM endpoint は poll 型 config を使う
- step ごとに `process_recv_events()` を呼ぶ
- `recv_dict()` / `recv()` で pull 受信する

subscription API は将来利用可能だが、初期の robot sync ライブラリでは必須にしない。

## `godot_sync.yaml`

### 位置づけ

`viewer.recipe.yaml` は engine-independent であるべきなので、
Godot 固有設定をそこへ混ぜない。

その代わり、`hakoniwa-mbody-registry` 側に
**Godot 用の薄い overlay 設定**として `godot_sync.yaml` を置く。

方針:

- `viewer.recipe.yaml`
  - engine-independent
- `godot_sync.yaml`
  - Godot runtime 反映に必要な最小設定
- `robot_sync.profile.json`
  - generator が出力する最終生成物

### 目的

`godot_sync.yaml` には、ユーザが手で意味を決める必要があるが、
scene generator だけでは自動推論しにくい情報だけを書く。

例:

- base pose 用 PDU 名
- joint_states 用 PDU 名
- 同期対象 joint 名
- 回転軸
- 符号
- 初期オフセット
- 利用する座標変換 rule

### 入力例

```yaml
robot_name: TB3

pdu:
  base: base_link_pos
  joints: joint_states

coordinate_system:
  position_rule: hakoniwa_to_godot
  rotation_rule: hakoniwa_to_godot

joints:
  - joint_name: wheel_left_joint
    body_name: wheel_left_link
    axis: z
    sign: 1.0
    offset_rad: 0.0

  - joint_name: wheel_right_joint
    body_name: wheel_right_link
    axis: z
    sign: 1.0
    offset_rad: 0.0
```

### 設計意図

`godot_sync.yaml` では `node_path` を直接書かせない。

代わりに:

- `body_name`
- `joint_name`

を入力にし、最終的な Godot `node_path` は
`hakoniwa-mbody-registry` 側 generator が scene 生成規則に従って確定する。

これにより、利用者に `RosToGodot/Visuals/...` のような
生成都合の path を意識させずに済む。

## Generated JSON Profile

### 基本方針

最終 profile JSON は **宣言的**に保つ。

入れてよいもの:

- 名前
- path
- 軸
- 符号
- offset
- 既知の変換ルール名

入れないもの:

- 任意スクリプト
- 任意式
- eval 相当の動的処理

### 最小構造

```json
{
  "version": 1,
  "robot_name": "TB3",
  "base_link_pdu_name": "base_link_pos",
  "joint_states_pdu_name": "joint_states",
  "base_node_path": "Visuals/base_link",
  "coordinate_system": {
    "position_rule": "hakoniwa_to_godot",
    "rotation_rule": "hakoniwa_to_godot"
  },
  "joint_mappings": [
    {
      "joint_name": "wheel_left_joint",
      "node_path": "Visuals/base_link/wheel_left_link",
      "axis": "z",
      "sign": 1.0,
      "offset_rad": 0.0,
      "apply_mode": "basis_delta"
    },
    {
      "joint_name": "wheel_right_joint",
      "node_path": "Visuals/base_link/wheel_right_link",
      "axis": "z",
      "sign": 1.0,
      "offset_rad": 0.0,
      "apply_mode": "basis_delta"
    }
  ]
}
```

これは利用者が直接編集する一次設定ではなく、
`godot_sync.yaml` と scene 生成規則から得られる最終生成物である。

### 必須項目

- `version`
- `robot_name`
- `base_link_pdu_name`
- `joint_states_pdu_name`
- `base_node_path`
- `coordinate_system`
- `joint_mappings`

### `coordinate_system`

初期実装では profile から自由に行列を与えず、
ライブラリが知っている rule 名を選ぶ形にする。

例:

- `identity`
- `hakoniwa_to_godot`
- `ros_to_godot`

これにより、変換実装の責任を GDScript 側へ固定できる。

## `target_root_path` と profile path の関係

scene 構成上の root 名は robot ごと、project ごとに異なりうる。

例えば以下はどれもありえる。

- `Root/RosToGodot/...`
- `RobotRoot/Visuals/...`
- `MyRobot/Model/...`

現状の `hakoniwa-mbody-registry` 生成器は `RosToGodot` を固定名で出力するが、
ライブラリ設計としてそれを必須前提にはしない。

方針:

- controller は `target_root_path` を持つ
- profile の `base_node_path` と `joint_mappings[].node_path` は
  **target root からの相対 path** とする

例:

- `target_root_path = "Root/RosToGodot"`
- `base_node_path = "Visuals/base_link"`
- `joint_mappings[].node_path = "Visuals/base_link/wheel_left_link"`

これにより、scene 側の subtree 名と robot profile を疎結合に保てる。

`hakoniwa-mbody-registry` が生成する標準 scene では `target_root_path` は
`RosToGodot` またはその親付き path になることが多いが、
`HakoniwaRobotSyncController` は固定値を仮定しない。

### `joint_mappings`

各 joint で指定する項目:

- `joint_name`
  - `JointState.name[]` に入る名前
- `node_path`
  - `target_root_path` 基準の相対 path
- `axis`
  - `x`, `y`, `z`
- `sign`
  - `1.0` または `-1.0`
- `offset_rad`
  - 初期オフセット角
- `apply_mode`
  - 初期案では `basis_delta` を標準にする

将来候補:

- `position_index`
- `velocity_index`
- `effort_index`
- `ignore_missing`

ただし初期実装では `joint_name` ベース lookup を優先する。

## joint 適用方針

### 基本原則

- `JointState.name[]` と `position[]` から名前ベースで値を引く
- scene node ごとに初期 `Basis` を保持する
- 毎 frame で直接絶対回転を上書きするのではなく、
  初期 `Basis` に対して差分角を適用する

### 適用式

概念上は以下。

```text
applied_angle = sign * joint_position + offset_rad
node_basis = initial_basis * axis_rotation(applied_angle)
```

### 欠損時挙動

- `joint_name` が message に存在しない
  - warn を出す
  - その joint は更新しない
- `node_path` が scene に存在しない
  - setup failure とする
- `joint_mappings` が空
  - validate error とする

## base body 適用方針

base pose は joint と別責務で扱う。

対象:

- position
- orientation

考え方:

- base body は `base_node_path` に反映する
- `base_node_path` は `target_root_path` 基準で resolve する
- position / rotation は `coordinate_system` の rule を通して Godot に変換する
- child joints は base body の子孫 node として相対回転のみを適用する

## エラーハンドリング

初期段階では fail-fast を優先する。

setup 時 failure:

- profile file が存在しない
- JSON parse に失敗
- 必須項目が不足
- endpoint bind に失敗
- scene node path が存在しない

runtime 時 failure:

- receive が一時的に空
  - error にせず skip
- `JointState` に一部 joint が無い
  - warn
- decode に失敗
  - warn を出して当該 frame の反映を skip

## 既存 API との関係

このライブラリは以下の既存 API の上に載る。

- `HakoniwaSimNode`
- `HakoniwaEndpointNode`
- `HakoniwaTypedEndpoint`

設計上の位置づけ:

- `hakoniwa-godot` 本体
  - transport / codec / time sync を提供
- `hakoniwa_robot_sync`
  - robot model への反映を提供

つまり `hakoniwa_robot_sync` は、
PDU 受信そのものを再実装せず、
既存 endpoint API を利用する上位ライブラリとして実装する。

## 将来拡張

将来追加したい候補:

- profile 切り替え UI
- editor helper
- velocity / effort の利用
- base pose 補間
- 複数 body 同時同期
- URDF / MJCF から profile JSON を半自動生成する tooling

ただし、初期の完成条件は以下に置く。

## 初期完成条件

1. `tb3_reference_sync.gd` の共通ロジックを addon へ移せる
2. TB3 profile JSON 1 つで既存 scene が動く
3. `joint_states` の wheel 回転が profile 経由で反映される
4. base body pose が profile 経由で反映される
5. 新 robot は script 複製ではなく profile 追加で導入できる

## 次ステップ

実装に入る前に、以下を決める。

1. `godot_sync.yaml` の最終フィールド名
2. base pose message の前提型
3. `coordinate_system` rule の初期セット
4. TB3 用 `godot_sync.yaml` の実データ
5. 生成される profile JSON の出力先
6. `addons/hakoniwa_robot_sync` を本 repo に同梱するか、別 addon に分けるか
