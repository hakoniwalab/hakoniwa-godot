# Installation

この文書は、**ビルド済み addon を既存の Godot プロジェクトへ導入する利用者向け手順**です。  
ソースから build したい場合は [developer_build.md](developer_build.md) を参照してください。

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

### 4. 導入状態を確認する

導入先プロジェクトで最低限これを確認してください。

- `addons/hakoniwa/plugin.cfg` が存在する
- `addons/hakoniwa/hakoniwa.gdextension` が存在する
- `addons/hakoniwa/bin/` に対象 OS 向け native library がある
- `addons/hakoniwa/codecs/` に必要 codec の `.gdextension` と shared library がある
- typed message class を使う場合は `addons/hakoniwa_msgs/<package>/` がある

## 初回動作確認

最小の確認は `examples/basic_subscriber` 相当のロード確認です。

```bash
<GODOT_BIN> --headless --path examples/basic_subscriber --quit
```

成功すると、最後に `HAKONIWA_CODEC_SMOKE_OK` が出ます。

## `core_pro_two_asset` を試す場合

`core_pro_two_asset` のように複数 codec を前提にする example は、必要 codec が揃っている必要があります。  
配布物に不足 codec が含まれていない場合は、開発者向け手順で `all` codec artifact を作ってください。

既知の安定起動手順:

```bash
# terminal 1
bash tools/run_core_pro_conductor.sh

# terminal 2
cd examples/core_pro_two_asset
python python_controller.py config/comm/pdu_def.json

# terminal 3
<GODOT_BIN> --headless --path examples/core_pro_two_asset
```

physics 同期確認時:

```bash
HAKO_ENABLE_PHYSICS_TIME_SYNC=1 HAKO_DEBUG_TIME_SYNC_LOGS=1 <GODOT_BIN> --headless --path examples/core_pro_two_asset
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
