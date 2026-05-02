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
cmake --preset windows-default
cmake --preset windows-common-codecs
cmake --preset windows-all-codecs
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

Windows ネイティブで build する場合:

```powershell
cmake --preset windows-all-codecs
cmake --build --preset windows-all-codecs-release
```

## codec / message addon

補助ツール:

- `tools/codec_plugin_tool.sh`
  - codec plugin の configure / build / test / 出力先確認
- `tools/message_addon_tool.sh`
  - generated GDScript message class を `addons/hakoniwa_msgs` へ同期
- `tools/build_all_codecs.sh`
  - 全 codec の configure / build / message addon 同期を一括実行
- `tools/build_all_codecs.ps1`
  - Windows ネイティブ CMake で全 codec build と message addon 同期を一括実行
- `tools/build_all_codecs_wsl.sh`
  - WSL2 の Bash から `powershell.exe` 経由で `tools/build_all_codecs.ps1` を起動
  - `--dependency-build minimal|full` で `hakoniwa-core-pro` の build 範囲を切り替え

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

WSL2 から Windows ネイティブで一括 build する場合:

```bash
bash tools/build_all_codecs_wsl.sh --config Release
```

`minimal` は addon/runtime に不要な `hakoniwa-core-pro` の command / examples / python bindings を無効化する。
依存込みでフル確認したい場合だけ `--dependency-build full` を使う。

`BoostConfig.cmake` が見つからない場合は、Windows 側で `vcpkg` に
`boost-asio:x64-windows` と `boost-beast:x64-windows` を入れ、toolchain を渡す:

```bash
bash tools/build_all_codecs_wsl.sh \
  --clean \
  --config Release \
  --toolchain-file /mnt/c/project/vcpkg/scripts/buildsystems/vcpkg.cmake \
  --vcpkg-triplet x64-windows
```

`tests/integration/core_pro_two_asset` のように複数 codec を使う integration test の前には、`all` で揃えるのが一番確実です。

Windows で最小確認を回す場合は、まず codec smoke、その次に core-pro smoke を使う。

codec smoke:

```bash
bash tools/run_codec_smoke_wsl.sh --godot-bin /mnt/c/path/to/Godot.exe --quit
```

成功条件は `HAKONIWA_CODEC_SMOKE_OK` です。

core-pro smoke:

```bash
bash tools/run_core_pro_smoke_wsl.sh \
  --godot-bin /mnt/c/path/to/Godot_console.exe
```

成功条件は `HAKO_CORE_SMOKE_OK` です。

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
pwsh -File tools/build_all_codecs.ps1 -Configuration Release -DependencyBuild minimal -Packages all
pwsh -File tools/addon_artifact_tool.ps1 stage   -Platform windows -Arch x86_64 -Packages all
pwsh -File tools/addon_artifact_tool.ps1 archive -Platform windows -Arch x86_64 -Packages all
```

WSL2 から Windows release build と artifact 作成まで行う場合:

```bash
bash tools/build_all_codecs_wsl.sh \
  --clean \
  --config Release \
  --dependency-build minimal \
  --toolchain-file /mnt/c/project/vcpkg/scripts/buildsystems/vcpkg.cmake \
  --vcpkg-triplet x64-windows \
  --boost-dir /mnt/c/project/vcpkg/installed/x64-windows/share/boost

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tools/addon_artifact_tool.ps1)" stage   -Platform windows -Arch x86_64 -Packages all
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tools/addon_artifact_tool.ps1)" archive -Platform windows -Arch x86_64 -Packages all
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
