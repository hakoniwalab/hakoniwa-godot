# 📦 hakoniwa-godot

> **Godot を箱庭に接続する最小構成**

**hakoniwa-godot** は、Godot Engine を箱庭（Hakoniwa）と接続するための統合パッケージです。  
ゲームエンジンを単なる可視化ツールとしてではなく、**分散シミュレーションの一部として動作させる** ことを目的としています。

---

## 🎯 Target Users

* ロボット / ドローン研究者
* シミュレーション開発者
* Godot ユーザーで外部システムと連携したい人

---

## 🧠 Architecture

hakoniwa-godot は 3 つのコア機能で構成されます。

```text
時間（Time）  ＋  状態（State）  ＋  操作（Control）
```

これにより、Godot は単なる描画エンジンではなく、**箱庭に接続された 1 つの実行ノード** として動作します。

| コンポーネント | 役割 | 状態 |
|---|---|---|
| `hakoniwa-core-pro` | 時刻同期。外部シミュレーションと同じ時間軸で動作する | ✅ Done |
| `hakoniwa-pdu-endpoint` | PDU ベースのデータ通信 (`latest` / `queue`) | ✅ Done |
| `hakoniwa-pdu-rpc` | RPC による外部システムの制御・状態取得 | 🔜 Next |

---

## 📡 Data Handling Modes

Godot のフレームループとの連携指針:

| Godot Loop | 推奨モード | 用途 |
|---|---|---|
| `_process()` | `latest` | 可視化・UI 更新 |
| `_physics_process()` | `queue` | 状態遷移・ログ・制御 |

---

## ⏱️ Physics Time Sync

`HakoniwaSimNode` は、Hakoniwa world time と Godot physics time の同期をオプションで有効化できます。

- 通常利用では、`HakoniwaSimNode` をシーンに配置し、Inspector で `enable_physics_time_sync` を設定する
- `auto_sync_delta_time_with_physics` が有効な場合、`delta_time_usec` は Godot の physics `ΔT` から自動計算される
- world time が不足している場合、asset step は `BLOCKED_BY_WORLD_TIME` に入り、条件が揃うと再開する
- UI を停止させたくないノードは `process_mode = Always` を明示設定する

headless 実行や比較実験では、環境変数でも切り替えできる。

```bash
HAKO_ENABLE_PHYSICS_TIME_SYNC=1 HAKO_DEBUG_TIME_SYNC_LOGS=1 /Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path examples/core_pro_two_asset
```

詳細仕様:

- [docs/physics_time_sync_strategy.md](/Users/tmori/project/oss/hakoniwa-godot/docs/physics_time_sync_strategy.md:1)
- [docs/physics_time_sync_impl.md](/Users/tmori/project/oss/hakoniwa-godot/docs/physics_time_sync_impl.md:1)

---

## ✅ Current Status

> 現在のマイルストーン: **`HakoniwaSimNode + internal SHM endpoint + Python controller` による 2 asset 時刻同期・typed PDU 通信まで**

達成済み:

* Godot プラグインの最小土台を作成
* GDExtension のビルドに成功
* `hakoniwa-pdu-endpoint` へのリンク確認
* `open / start / stop / is_running` の最小 API を実装
* `send_by_name / recv_by_name` による `latest` 動作確認
* `recv_next()` による `queue` 動作確認
* `set_recv_event / get_pending_count` による pending 管理確認
* `HakoniwaCodecRegistry` による codec plugin load に成功
* `hako_msgs` codec plugin の `encode / decode` smoke test に成功
* message package ごとの shared library plugin 生成基盤を追加
* `HakoniwaEndpointNode` による GDScript wrapper を追加
* `HakoniwaTypedEndpoint` による `robot + pdu_name` 束縛 API を追加
* `addons/hakoniwa_msgs` 生成導線を追加
* typed endpoint で単純型、複雑型、可変長配列の動作確認
* `HakoniwaSimNode` による `hakoniwa-core-pro` polling asset 統合
* start / stop / reset / restart lifecycle smoke に成功
* `simtime == world_time` の `core_pro_smoke` に成功
* `HakoniwaSimNode + internal SHM endpoint + Python controller` の 2 asset smoke に成功
* `geometry_msgs/Twist` の `motor` / `pos` で typed PDU 相互通信に成功
* `HakoniwaEndpointNode` に low-level pull API と ROS 風 subscription API を実装
* internal SHM endpoint では `tick()` 経由で `dispatch_recv_events()` が動作
* codec `.gdextension` 初期化順を framework 側で吸収
* addon artifact の staging / archive 導線を整備
  - macOS / Linux: `tools/addon_artifact_tool.sh`
  - Windows: `tools/addon_artifact_tool.ps1`

まだ対象外:

* `hakoniwa-pdu-rpc` の操作系統合
* codec plugin / message addon の自動 discovery
* Windows 実機での build / load 回帰確認

---

## 🔢 Verified Environment

2026-03-22 時点:

* Godot `4.6.1` (mono) on macOS arm64
* `godot-cpp` submodule: `4.5` branch

> 注記: `godot-cpp` の公式 `4.6` branch が 2026-03-22 時点で存在しないため、現時点では `4.5` 系を採用しています。

---

## 📦 Distribution Model

```text
addons/
├─ hakoniwa/
│  ├─ bin/          # platform 依存: native binary
│  ├─ codecs/       # platform 依存: codec plugin
│  └─ scripts/      # platform 非依存: GDScript wrapper
└─ hakoniwa_msgs/   # platform 非依存: generated GDScript message classes
```

`addons/hakoniwa` は `OS + architecture` ごとに配布物が分かれます。  
`addons/hakoniwa_msgs` は platform 非依存の message 定義層として独立して扱います。

このリポジトリでは `addons/` 自体を正本にはせず、source から生成・配布する成果物として扱います。

現状の release 状態:

* `macOS arm64` は build / artifact 手順とも確認済み
* `Linux` は artifact tool が対応している
* `Windows x86_64` は artifact tool が対応している
* ただし回帰確認の基準 platform は引き続き `macOS arm64`

**common codecs**:

`builtin_interfaces`, `can_msgs`, `drone_srv_msgs`, `ev3_msgs`, `geometry_msgs`, `hako_mavlink2_msgs`, `hako_mavlink_msgs`, `hako_msgs`, `hako_srv_msgs`, `mavros_msgs`, `nav_msgs`, `sensor_msgs`, `std_msgs`, `tf2_msgs`

---

## 🚀 Quick Start

### Prerequisites

* Godot `4.6.1` (mono) on macOS arm64
* CMake `>= 3.21`
* submodule 含む clone (`--recursive`)

---

### 1. Clone

```bash
git clone --recursive https://github.com/hakoniwalab/hakoniwa-godot.git
cd hakoniwa-godot
```

---

### 2. Build Native Extension

```bash
cmake --preset default
cmake --build --preset default
```

preset オプション:

```bash
cmake --preset default        # hako_msgs のみ
cmake --preset common-codecs  # common codecs
cmake --preset all-codecs     # 全 package
```

package を直接指定する場合:

```bash
cmake -S . -B build -DHAKONIWA_GODOT_CODEC_PACKAGES="hako_msgs;std_msgs;geometry_msgs"
cmake --build build -j4
```

全 codec を明示指定する場合:

```bash
cmake -S . -B build -DHAKONIWA_GODOT_CODEC_PACKAGES="all"
cmake --build build -j4
```

補助ツール:

- `tools/codec_plugin_tool.sh`
  - codec plugin の configure / build / test / 出力先確認を行う
- `tools/message_addon_tool.sh`
  - generated GDScript message class を `addons/hakoniwa_msgs` へ同期する
- `tools/build_all_codecs.sh`
  - 全 codec の configure / build / message addon 同期を一括実行する
- `tools/run_core_pro_conductor.sh`
  - `hakoniwa-core-pro` conductor を単独起動する
- `tools/run_core_pro_two_asset_controller.sh`
  - `core_pro_two_asset` 用 Python controller を単独起動する

```bash
bash tools/codec_plugin_tool.sh list
bash tools/codec_plugin_tool.sh configure --packages "hako_msgs;std_msgs"
bash tools/codec_plugin_tool.sh configure --packages all
bash tools/codec_plugin_tool.sh build --target hako_msgs_codec
bash tools/codec_plugin_tool.sh build
bash tools/codec_plugin_tool.sh test
bash tools/message_addon_tool.sh sync --packages \"hako_msgs;std_msgs\"
bash tools/message_addon_tool.sh sync --packages all
```

codec と message addon を一括で生成・配置する場合:

```bash
bash tools/build_all_codecs.sh
```

このスクリプトは次をまとめて実行する:

- `tools/codec_plugin_tool.sh configure --packages all`
- `tools/codec_plugin_tool.sh build`
- `tools/message_addon_tool.sh sync --packages all`

`core_pro_two_asset` のように複数 codec を前提にする example を動かす前には、この一括実行を推奨する。
特に不足 codec の `.gdextension` load error を避けたい場合は、`all` で揃えるのが一番確実である。

`core_pro_two_asset` の既知の安定起動手順:

```bash
# terminal 1
bash tools/run_core_pro_conductor.sh

# terminal 2
cd examples/core_pro_two_asset
python python_controller.py config/comm/pdu_def.json

# terminal 3
/Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path /Users/tmori/project/oss/hakoniwa-godot/examples/core_pro_two_asset
```

physics 同期確認時は terminal 3 の Godot 起動に環境変数を付ける:

```bash
HAKO_ENABLE_PHYSICS_TIME_SYNC=1 HAKO_DEBUG_TIME_SYNC_LOGS=1 /Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path /Users/tmori/project/oss/hakoniwa-godot/examples/core_pro_two_asset
```

Python controller には `config/comm/pdu_def.json` を渡すこと。`endpoint_shm_with_pdu.json` は Godot endpoint 用設定であり、Python 側には使わない。

macOS addon artifact を作る場合:

```bash
bash tools/addon_artifact_tool.sh stage   --platform macos --arch arm64 --packages all
bash tools/addon_artifact_tool.sh archive --platform macos --arch arm64 --packages all
```

Linux artifact の例:

```bash
bash tools/addon_artifact_tool.sh stage   --platform linux --arch x86_64 --packages all
bash tools/addon_artifact_tool.sh archive --platform linux --arch x86_64 --packages all
```

Windows artifact の例:

```powershell
pwsh -File tools/addon_artifact_tool.ps1 stage   -Platform windows -Arch x86_64 -Packages all
pwsh -File tools/addon_artifact_tool.ps1 archive -Platform windows -Arch x86_64 -Packages all
```

出力先:

```text
dist/hakoniwa-godot-macos-arm64/
dist/hakoniwa-godot-macos-arm64.tar.gz
```

---

### 3. Run Example

```bash
# macOS arm64 環境での実行例
/Applications/Godot_mono.app/Contents/MacOS/Godot --path examples/basic_subscriber
```

---

### 4. Verify

```bash
cmake --preset default
cmake --build --preset default
bash tools/message_addon_tool.sh sync --packages all
/Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path examples/basic_subscriber --quit
ctest --preset default
```

期待される出力:

```text
Godot Engine v4.6.1.stable.mono.official.14d19694e - https://godotengine.org

hakoniwa-pdu-endpoint
true
true
0
{ "robot": "drone0", "channel_id": 0, "pdu_name": "sample_state", "timestamp_ns": 0, "value": { "data": 72623859790382856 } }
3
{ "robot": "drone0", "channel_id": 0, "pdu_name": "sample_state", "timestamp_ns": 0, "value": { "data": 10 } }
2
{ "robot": "drone0", "channel_id": 0, "pdu_name": "sample_state", "timestamp_ns": 0, "value": { "data": 11 } }
1
{ "robot": "drone0", "channel_id": 0, "pdu_name": "sample_state", "timestamp_ns": 0, "value": { "data": 12 } }
0
{  }
{ "robot": "drone0", "channel_id": 1, "pdu_name": "sample_pose", "timestamp_ns": 0, "value": { "position": { "x": 1.25, "y": 2.5, "z": 3.75 }, "orientation": { "x": 0.0, "y": 0.5, "z": 0.0, "w": 1.0 } }, "typed_value": <RefCounted...> }
{ "robot": "drone0", "channel_id": 2, "pdu_name": "sample_multi", "timestamp_ns": 0, "value": { "layout": { "dim": [{ "label": "rows", "size": 2, "stride": 6 }, { "label": "cols", "size": 3, "stride": 3 }], "data_offset": 0 }, "data": [100, 101, 102, 200, 201, 202] }, "typed_value": <RefCounted...> }
HAKONIWA_CODEC_SMOKE_OK
```

確認内容:

* GDExtension のロードと `HakoniwaPduEndpoint` クラスの登録
* `hakoniwa-pdu-endpoint` C API 呼び出しの成立
* `latest` モードで `std_msgs/UInt64` の typed decode
* `queue` モードで `recv_next()` と pending count `3 → 2 → 1 → 0`
* `hako_msgs_codec`, `std_msgs_codec`, `geometry_msgs_codec` のロード
* `geometry_msgs/Pose`, `std_msgs/UInt64MultiArray` の typed endpoint
* `geometry_msgs/Twist` による `motor` / `pos` の endpoint-only typed send / recv

codec smoke test:

```text
1/1 Test #1: hakoniwa_codec_smoke .............   Passed
100% tests passed, 0 tests failed out of 1
```

---

## ⏭ Next Steps

* `hakoniwa-pdu-rpc` を組み込み、操作系 API を追加する
* codec plugin / message addon の auto-discovery を検討する
* `addons/hakoniwa_msgs` の正式配布導線を整える
* CI で addon artifact を自動生成する
* Windows / Linux の実機回帰確認を追加する

## Notes

- 通常利用では `HakoniwaSimNode` または `HakoniwaEndpointNode` を使う
- codec plugin path は `res://addons/hakoniwa/codecs/<package>_codec` のように拡張子なしを推奨する
- `HakoniwaCodecRegistry` を直接使うのは low-level 利用とし、codec の `.gdextension` 初期化順を理解している場合に限る
- `HakoniwaEndpointNode` は low-level pull API と ROS 風 subscription API の両方を持つ
- high-level subscription API を使う場合、対象 endpoint JSON の entry で `notify_on_recv: true` が必要
- `addons/hakoniwa_msgs` は platform 非依存なので、Windows でも追加対応は基本不要
- codec plugin の `.gdextension` は Windows `.dll` entry を持つが、Windows 実機での build / load 確認はまだしていない

詳細:

- [installation.md](/Users/tmori/project/oss/hakoniwa-godot/docs/installation.md)
- [api_overview.md](/Users/tmori/project/oss/hakoniwa-godot/docs/api_overview.md)
- [troubleshooting.md](/Users/tmori/project/oss/hakoniwa-godot/docs/troubleshooting.md)

---

## 📂 Repository Structure

```text
hakoniwa-godot/
├─ addons/          # Godot addon package
├─ native/          # GDExtension (C++)
├─ third_party/
│  ├─ godot-cpp
│  └─ hakoniwa-pdu-endpoint
├─ examples/
└─ docs/
```

---

## 🔗 Dependencies / Related Projects

コアコンポーネント:

* [hakoniwa-pdu-endpoint](https://github.com/hakoniwalab/hakoniwa-pdu-endpoint) - PDU 通信ライブラリ
* [hakoniwa-core-pro](https://github.com/hakoniwalab/hakoniwa-core-pro) - 時刻同期エンジン
* [hakoniwa-pdu-rpc](https://github.com/hakoniwalab/hakoniwa-pdu-rpc) - RPC 通信
