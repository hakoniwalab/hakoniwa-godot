# Quick Start

この文書は、**まず最短で `HakoniwaSimNode` を動かしたい利用者向け**です。  
既存 Godot プロジェクトへの導入方法や Inspector 設定の意味は [installation.md](installation.md) を参照してください。

## この quick start のゴール

次の 3 段階だけを確認します。

1. `conductor` を起動する
2. `HakoniwaSimNode` を使う Godot project を起動する
3. `hako-cmd start` で simulation を開始し、ログが流れることを確認する

ここでは **PDU 通信や Python controller までは含めません**。  
まずは「Godot が Hakoniwa asset として参加し、start で動き始める」ことを確認するのが目的です。

## 前提

- `hakoniwa-godot` が build 済みである
- `HakoniwaSimNode` を使う既存 Godot project がある
- その project 側で `addons/hakoniwa` が使える状態になっている

既存プロジェクトへの addon 配置や `HakoniwaSimNode` の基本設定は [installation.md](installation.md) を参照してください。

## Known-Good 手順

### 1. conductor を起動する

`hakoniwa-godot` リポジトリ側で conductor を起動します。

```bash
cd /path/to/hakoniwa-godot
bash tools/run_core_pro_conductor.sh
```

### 2. Godot project を起動する

次に、`HakoniwaSimNode` を使う Godot project を起動します。

たとえば `sample.gd` が `HakoniwaSimNode` を使う scene を持っているなら、その scene まで立ち上げます。

```bash
<GODOT_BIN> --path /path/to/your_godot_project
```

この段階では、まだ simulation は開始しません。  
Godot 側が asset として登録され、開始待ち状態に入ることが重要です。

`sample.gd` と `HakoniwaSimNode` の known-good 設定例:

![Quick Start sample.gd and HakoniwaSimNode](images/quick_start_sample_gd.png)

この例では、quick start 用に次の最小構成を使っています。

- `Use Internal Shm Endpoint`: オフ
- `Delta Time (usec)`: `20000`
- `Auto Initialize on Ready`: オン
- `Auto Tick on Physics Process`: オン
- `Enable Physics Time Sync`: オン
- `sample.gd`: `simulation_started` と `simulation_step` を受けてログを出すだけ

各設定項目の意味:

- `Asset Name`
  - 箱庭の中でこの Godot asset を識別する名前です
  - `hako-cmd start` で simulation を開始したとき、この名前の asset として参加します
- `Delta Time (usec)`
  - Godot asset が 1 step で進める simulation time です
  - `20000` は `20ms` を意味します
- `Auto Initialize on Ready`
  - scene の `_ready()` 時に `HakoniwaSimNode.initialize()` を自動で呼びます
  - quick start では手動初期化を省きたいので `オン` が自然です
- `Auto Tick on Physics Process`
  - Godot の `_physics_process()` ごとに `HakoniwaSimNode` の step 処理を自動で進めます
  - quick start では利用者が自分で `tick()` 相当を呼ばなくてよいように `オン` にします
- `Enable Physics Time Sync`
  - Hakoniwa world time と Godot physics step を厳密に同期させるモードです
  - quick start の known-good 設定では `オン` にします
  - これにより Godot の physics step と Hakoniwa の進行を揃えた状態で `simulation_step` のログを確認できます
- `Use Internal Shm Endpoint`
  - `HakoniwaSimNode` の中に PDU 通信用 endpoint を持たせる設定です
  - Python controller や他 asset と通信するときに使います
  - quick start では時刻同期と start 動作だけを確認したいので `オフ` にします

### 3. `hako-cmd start` を実行する

別端末で simulation を開始します。

```bash
hako-cmd start
```

これで Godot 側の `simulation_started` / `simulation_step` に対応するログが流れ始めれば成功です。

## 成功条件

最低限、次のどちらかが見えれば quick start 成功とみなします。

- `simulation started` 相当のログが出る
- `simulation_step` に対応する step ログが継続して流れる

`sample.gd` の既知のログ例:

```text
Godot Engine v4.6.1.stable.mono.official.14d19694e - https://godotengine.org
Metal 4.0 - Forward+ - Using Device #0: Apple - Apple M2 Pro (Apple8)

simulation started
step simtime=16667 world=20000
step simtime=33334 world=40000
step simtime=50001 world=60000
step simtime=66668 world=80000
step simtime=83335 world=90000
step simtime=100002 world=110000
step simtime=116669 world=130000
step simtime=133336 world=140000
step simtime=150003 world=160000
step simtime=166670 world=180000
step simtime=183337 world=190000
step simtime=200004 world=210000
```

利用者側の最小 script は、たとえば次のようなものです。

```gdscript
extends Node

@onready var sim: HakoniwaSimNode = $HakoniwaSimNode

func _ready() -> void:
	sim.simulation_started.connect(_on_simulation_started)
	sim.simulation_step.connect(_on_simulation_step)

func _on_simulation_started() -> void:
	print("simulation started")

func _on_simulation_step(simtime_usec: int, world_time_usec: int) -> void:
	print("step simtime=%d world=%d" % [simtime_usec, world_time_usec])
```

## この次にやること

quick start が通ったら、次は用途に応じて進みます。

- 既存プロジェクトへ addon を持ち込む
  - [installation.md](installation.md)
- PDU 通信を追加する
  - `HakoniwaSimNode` の internal SHM endpoint を使う example
- typed message や codec plugin を使う
  - [developer_build.md](developer_build.md)
