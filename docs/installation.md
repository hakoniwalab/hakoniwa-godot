# Installation

この文書は、**ビルド済み addon を既存の Godot プロジェクトへ導入する利用者向け手順**です。  
ソースから build したい場合は [developer_build.md](developer_build.md) を参照してください。

まず最短で `HakoniwaSimNode` を動かしたい場合は、先に [quick_start.md](quick_start.md) を参照してください。

## 対応環境

- Godot `4.6.1` (mono)
- `macOS arm64`
  - 最も確認できている基準 platform
- `Linux x86_64`
  - artifact 導線あり
  - ただし `macOS arm64` ほど回帰確認は厚くない
- `Windows x86_64`
  - artifact 導線あり
  - ただし `macOS arm64` ほど回帰確認は厚くない

## 何を配置するか

既存プロジェクトには、最終的に次を `addons/` 配下へ置きます。

- `addons/hakoniwa`
- `addons/hakoniwa_msgs`  
  typed message class を使う場合のみ

## 導入手順

### 1. ビルド済み配布物を用意する

想定する入力は、`hakoniwa-godot` の build 済み addon artifact です。

例:

- `hakoniwa-godot-macos-arm64.tar.gz`
- `hakoniwa-godot-linux-x86_64.tar.gz`
- `hakoniwa-godot-windows-x86_64.zip`

自分で build する場合は [developer_build.md](developer_build.md) を参照してください。

### 2. 既存プロジェクトへ配置する

配布物を展開し、対象 Godot プロジェクトの `addons/` 配下へコピーします。

```bash
cp -R addons/hakoniwa /path/to/your_godot_project/addons/
cp -R addons/hakoniwa_msgs /path/to/your_godot_project/addons/
```

typed message class を使わない場合は、`addons/hakoniwa_msgs` は省略できます。

### 3. プラグインを有効化する

Godot Editor で対象プロジェクトを開き、次を確認します。

1. `Project Settings > Plugins`
2. `Hakoniwa` plugin を `Enable`

### 4. `HakoniwaSimNode` を配置する

最初の確認では、シーンへ `HakoniwaSimNode` を 1 つ配置します。

1. シーンを開く
2. `Node` を追加
3. `HakoniwaSimNode` を検索して追加
4. Inspector で最低限次を設定する

- `asset_name`
  - 箱庭上で使う asset 名
- `delta_time_usec`
  - asset の基本刻み時間
- `enable_physics_time_sync`
  - Godot physics と時刻同期したい場合に有効化する
- `use_internal_shm_endpoint`
  - internal SHM endpoint を使う場合に有効化する
- `shm_endpoint_config_path`
  - internal SHM endpoint を使う場合の config path

設定項目の意味:

- `asset_name`
  - 箱庭の中でこの Godot asset を識別する名前
  - 他 asset や controller から見える名前でもある
- `delta_time_usec`
  - 1 step で進める simulation time
  - 単位は `usec`。`20000` なら `20ms`
- `enable_physics_time_sync`
  - `true` にすると、Godot physics step と箱庭時刻を同期する
  - world time が足りない場合は step を止める
- `auto_sync_delta_time_with_physics`
  - `true` にすると、`delta_time_usec` を Godot physics 設定から自動計算する
  - 60Hz の場合は約 `16667 usec`
- `use_internal_shm_endpoint`
  - `true` にすると、`HakoniwaSimNode` の内部に PDU 通信用 endpoint を持つ
  - Python controller や他 asset とデータをやり取りしたい場合に使う
- `shm_endpoint_config_path`
  - internal SHM endpoint の設定ファイル
  - `use_internal_shm_endpoint = true` のときに必要
- `internal_endpoint_codec_packages`
  - internal SHM endpoint が使う message package の一覧
  - `use_internal_shm_endpoint = true` のときに、扱う message type に対応する package 名を入れる
  - 例: `std_msgs`
- `debug_time_sync_logs`
  - `true` にすると、`BLOCKED_BY_WORLD_TIME` や resume の debug log を出す

補足:

- 通常利用では、`HakoniwaSimNode` は Inspector で設定して使う
- headless 実験では、example 側で環境変数から上書きしている場合がある
- `enable_physics_time_sync` を使う場合、UI を止めたくないノードは `process_mode = Always` を明示設定する
- `internal_endpoint_codec_packages` は Inspector に表示されるが、実際に必要になるのは internal SHM endpoint を使う場合だけ
- 入力するのは `res://...` の plugin path ではなく package 名

### 5. 利用側スクリプトを追加する

`HakoniwaSimNode` を置いたら、次は自分のスクリプトから signal を受けて動かします。

最小の `sample.gd` 例と known-good な起動確認手順は [quick_start.md](quick_start.md) を参照してください。

この文書では、導入先プロジェクトへ script を追加する作業手順だけを扱います。

1. シーンの root node を選ぶ
2. `Attach Script` で新しい GDScript を作る
3. `HakoniwaSimNode` の signal を受けるコードを追加する
4. `@onready var sim = $HakoniwaSimNode` の node path を自分のシーン構成に合わせる

補足:

- `simulation_step` は simtime が実際に進んだときだけ呼ばれます
- `enable_physics_time_sync = true` の場合でも、監視やログ用途として `simulation_step` を使えます

### 6. 導入状態を確認する

導入先プロジェクトで最低限これを確認してください。

- `addons/hakoniwa/plugin.cfg` が存在する
- `addons/hakoniwa/hakoniwa.gdextension` が存在する
- `addons/hakoniwa/bin/` に対象 OS 向け native library がある
- `addons/hakoniwa/codecs/` に必要 codec の `.gdextension` と shared library がある
- typed message class を使う場合は `addons/hakoniwa_msgs/<package>/` がある

## 初回動作確認

最初に `HakoniwaSimNode` の起動確認だけをしたい場合は [quick_start.md](quick_start.md) を参照してください。

addon の load 確認だけを行うなら、`tests/smoke/basic_subscriber` の smoke を使えます。

```bash
<GODOT_BIN> --headless --path tests/smoke/basic_subscriber --quit
```

成功すると、最後に `HAKONIWA_CODEC_SMOKE_OK` が出ます。

## `python_pdu_minimal` を試す場合

`python_pdu_minimal` は、`HakoniwaSimNode` を置いた Godot project が Python controller と `geometry_msgs/Twist` を双方向にやり取りする最小 example です。

この example は `geometry_msgs` codec が必要です。

```bash
cmake -S . -B build -DHAKONIWA_GODOT_CODEC_PACKAGES="geometry_msgs"
cmake --build build -j4
```

既知の安定起動手順:

```bash
# terminal 1
bash tools/run_core_pro_conductor.sh

# terminal 2
bash tools/run_python_pdu_minimal_controller.sh
```

成功時の目印:

- Godot 側: `simulation started`, `motor=...`, `pos=...`
- Python 側: `HAKO_PYTHON_EP_ENDPOINT_READY`, `HAKO_PYTHON_EP_POST_START_OK`

Godot 側は完成済み project ではなく、既存 project に `sample.gd` と `config/` を持ち込んで試します。  
Python controller には `config/endpoint_shm_callback_with_pdu.json` を渡します。  
Godot 側は `config/endpoint_shm_with_pdu.json` を internal endpoint 用に使います。

Inspector で internal SHM endpoint を設定する場合は、`Internal Endpoint Codec Packages` に internal endpoint で使う message package を入れてください。

例:

```text
geometry_msgs
```

## integration test を試す場合

`tests/integration/core_pro_two_asset` のように複数 codec を前提にする integration test は、必要 codec が揃っている必要があります。  
配布物に不足 codec が含まれていない場合は、開発者向け手順で `all` codec artifact を作ってください。

既知の安定起動手順:

```bash
# terminal 1
bash tools/run_core_pro_conductor.sh

# terminal 2
cd tests/integration/core_pro_two_asset
python python_controller.py config/comm/pdu_def.json

# terminal 3
<GODOT_BIN> --headless --path tests/integration/core_pro_two_asset
```

physics 同期確認時:

```bash
HAKO_ENABLE_PHYSICS_TIME_SYNC=1 HAKO_DEBUG_TIME_SYNC_LOGS=1 <GODOT_BIN> --headless --path tests/integration/core_pro_two_asset
```

## 注意

- `addons/hakoniwa/bin/` と `addons/hakoniwa/codecs/` は platform 依存です
- 異なる OS 向け binary を混在させないでください
- `addons/hakoniwa_msgs` は platform 非依存です
- `endpoint_shm_with_pdu.json` は Godot endpoint 用設定であり、Python controller には使いません

## 困ったとき

- codec や `.gdextension` の問題は [troubleshooting.md](troubleshooting.md)
- API の入口は [api_overview.md](api_overview.md)
- build / release / artifact 作成は [developer_build.md](developer_build.md)
