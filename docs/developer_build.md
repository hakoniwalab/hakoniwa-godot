# Developer Build Guide

この文書は、**ソースから `hakoniwa-godot` を build / package / release したい開発者向け**です。

## 前提

- Godot `4.6.1` (mono)
- CMake `>= 3.21`
- submodule 含む clone (`--recursive`)

```bash
git clone --recursive https://github.com/hakoniwalab/hakoniwa-godot.git
cd hakoniwa-godot
```

## 基本 build

```bash
cmake --preset default
cmake --build --preset default
```

preset:

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

全 codec を揃える場合:

```bash
cmake -S . -B build -DHAKONIWA_GODOT_CODEC_PACKAGES="all"
cmake --build build -j4
```

## codec / message addon

補助ツール:

- `tools/codec_plugin_tool.sh`
  - codec plugin の configure / build / test / 出力先確認
- `tools/message_addon_tool.sh`
  - generated GDScript message class を `addons/hakoniwa_msgs` へ同期
- `tools/build_all_codecs.sh`
  - 全 codec の configure / build / message addon 同期を一括実行

例:

```bash
bash tools/codec_plugin_tool.sh list
bash tools/codec_plugin_tool.sh configure --packages all
bash tools/codec_plugin_tool.sh build
bash tools/message_addon_tool.sh sync --packages all
```

一括:

```bash
bash tools/build_all_codecs.sh
```

`tests/integration/core_pro_two_asset` のように複数 codec を使う integration test の前には、`all` で揃えるのが一番確実です。

## 既知の単独起動補助

- `tools/run_core_pro_conductor.sh`
  - conductor 単独起動
- `tools/run_core_pro_two_asset_controller.sh`
  - `tests/integration/core_pro_two_asset` 用 Python controller 単独起動

## addon artifact 作成

### macOS arm64

```bash
bash tools/addon_artifact_tool.sh stage   --platform macos --arch arm64 --packages all
bash tools/addon_artifact_tool.sh archive --platform macos --arch arm64 --packages all
```

### Linux x86_64

```bash
bash tools/addon_artifact_tool.sh stage   --platform linux --arch x86_64 --packages all
bash tools/addon_artifact_tool.sh archive --platform linux --arch x86_64 --packages all
```

### Windows x86_64

```powershell
pwsh -File tools/addon_artifact_tool.ps1 stage   -Platform windows -Arch x86_64 -Packages all
pwsh -File tools/addon_artifact_tool.ps1 archive -Platform windows -Arch x86_64 -Packages all
```

## release 時の確認

- `addons/hakoniwa/bin/` に runtime library がある
- `addons/hakoniwa/codecs/` に対象 package の codec shared library と `.gdextension` がある
- `addons/hakoniwa/plugin.cfg` と `addons/hakoniwa/hakoniwa.gdextension` が含まれる
- `addons/hakoniwa/scripts/` が含まれる
- 必要なら `addons/hakoniwa_msgs/` が含まれる

## 生成物の扱い

codec plugin の package ごとの C++ source は、CMake configure 時に `build/` 配下へ生成されます。

代表例:

- `build/native/generated/hako_msgs/hako_msgs_codec_plugin.cpp`
- `build/native/generated/hako_msgs/hako_msgs_codec_plugin_init.cpp`

addon 側の出力物:

- `addons/hakoniwa/codecs/<package>_codec.<shared-library>`
- `addons/hakoniwa/codecs/<package>_codec.gdextension`
- `addons/hakoniwa_msgs/<package>/*.gd`

## 補足

- `addons/hakoniwa` は runtime 配布物
- `addons/hakoniwa_msgs` は platform 非依存の message 配布物
- release artifact は `OS + architecture` ごとに分ける
- `macOS arm64` が現在の基準 platform
- `Linux` / `Windows` は導線ありだが、回帰確認は `macOS` ほど厚くない
