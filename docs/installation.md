# Installation

## 目的

一般利用者が `hakoniwa-godot` を導入し、最初の動作確認まで進められるようにする。

## この文書に含める内容

- 対応 Godot バージョン
- 対応 OS / アーキテクチャ
- 依存関係
- リポジトリ取得方法
- ネイティブ拡張のビルド方法
- Godot プロジェクトへの組み込み方法
- 初回動作確認手順
- よくある導入失敗

## 初期ドラフト方針

実装が固まるまでは、以下の 2 系統を分けて書く。

1. 開発者向け導入
2. 利用者向け導入

初期段階では、まず開発者向け導入を先に成立させる。

## 配布の考え方

このプロジェクトは、論理的には `addons/hakoniwa` という 1 つの addon を提供する。

ただし、native binary を含むため、実際の配布物は platform ごとに分かれる。

- macOS
- Ubuntu / Linux
- Windows

さらに architecture も分かれる可能性がある。

一方で、GDScript や設定ファイルのような platform 非依存ファイルは共通である。

repo 上では `addons/` 自体を source of truth とせず、build と配布の結果として扱う。

つまり:

- source の正本は `native/`, `third_party/`, `tools/`, `docs/`
- `addons/hakoniwa` は runtime 配布物
- `addons/hakoniwa_msgs` は platform 非依存の message 配布物

ただし、現時点で最も確認できている release 手順は `macOS arm64` 向けである。

現状の整理:

- `macOS arm64`
  - build 確認済み
  - addon artifact 手順あり
  - release の基準 platform
- `Linux`
  - `addon_artifact_tool.sh` は対応している
  - shared library 拡張子 `.so` で artifact を切れる
  - ただし本 repo の回帰確認は macOS ほど厚くない
- `Windows`
  - `addon_artifact_tool.ps1` を正式導線として `x86_64` 向け artifact 作成に対応している
  - shared library 拡張子 `.dll` で artifact を切れる
  - archive は `.zip` を使う
  - ただし本 repo の回帰確認は macOS ほど厚くない

## M1 時点の前提

- 確認済み Godot: `4.6.1` on macOS
- `godot-cpp`: Git submodule の `4.5` ブランチを使用
- `hakoniwa-pdu-endpoint`: Git submodule を使用
- `hakoniwa-pdu-endpoint` の optional 機能は初期状態で無効化する
  - Zenoh: OFF
  - MQTT: OFF
  - Hakoniwa Core: OFF

`godot-cpp` は 2026-03-22 時点で公式 repo の `4.6` ブランチが存在しなかったため、M1 では `4.5` 系を固定値として採用する。

## 開発者向け導入手順

```bash
git clone --recursive https://github.com/hakoniwalab/hakoniwa-godot.git
cd hakoniwa-godot
cmake --preset default
cmake --build --preset default
```

ビルド成果物:

- `addons/hakoniwa/bin/libhakoniwa_godot_native.dylib`

`common codecs` を build した場合の代表的な出力:

- `addons/hakoniwa/codecs/hako_msgs_codec.<shared-library>`
- `addons/hakoniwa/codecs/std_msgs_codec.<shared-library>`
- `addons/hakoniwa/codecs/tf2_msgs_codec.<shared-library>`

`common codecs` は現在 build 実績のある package 群を指す。

addon artifact を作る場合:

```bash
bash tools/addon_artifact_tool.sh stage --platform macos --arch arm64 --packages all
bash tools/addon_artifact_tool.sh archive --platform macos --arch arm64 --packages all
```

生成先:

```text
dist/hakoniwa-godot-macos-arm64/
dist/hakoniwa-godot-macos-arm64.tar.gz
```

## addon release 手順

release は `addons/` をそのまま Git 正本として配るのではなく、source から artifact を再生成して切り出す前提にする。

推奨手順:

1. native addon を build する
2. codec plugin を必要 package ぶん build する
3. typed GDScript message class を `addons/hakoniwa_msgs` に同期する
4. `addon_artifact_tool.sh stage` で staging directory を作る
5. staging 内容を確認する
6. `addon_artifact_tool.sh archive` で archive を作る

`macOS arm64` の基準手順:

```bash
cmake --preset default
cmake --build --preset default

bash tools/codec_plugin_tool.sh configure --packages all
bash tools/codec_plugin_tool.sh build

bash tools/message_addon_tool.sh sync --packages all

bash tools/addon_artifact_tool.sh stage   --platform macos --arch arm64 --packages all
bash tools/addon_artifact_tool.sh archive --platform macos --arch arm64 --packages all
```

release 前に確認する内容:

- `addons/hakoniwa/bin/` に runtime library がある
- `addons/hakoniwa/codecs/` に対象 package の codec shared library と `.gdextension` がある
- `addons/hakoniwa/plugin.cfg` と `addons/hakoniwa/hakoniwa.gdextension` が含まれる
- `addons/hakoniwa/scripts/` が含まれる
- 必要なら `addons/hakoniwa_msgs/` が含まれる
- `examples/basic_subscriber` が通る
- `core_pro_smoke` と `core_pro_two_asset` の回帰が必要ならそのログも保存する

Linux 向けに artifact を切る場合の例:

```bash
bash tools/addon_artifact_tool.sh stage   --platform linux --arch x86_64 --packages all
bash tools/addon_artifact_tool.sh archive --platform linux --arch x86_64 --packages all
```

この場合、archive の中身は `.so` ベースになる。

Windows 向けに artifact を切る場合の例:

```powershell
pwsh -File tools/addon_artifact_tool.ps1 stage   -Platform windows -Arch x86_64 -Packages all
pwsh -File tools/addon_artifact_tool.ps1 archive -Platform windows -Arch x86_64 -Packages all
```

この場合、archive は `.zip` で、runtime / codec binary は `.dll` ベースになる。

重要:

- release artifact は `OS + architecture` ごとに分ける
- `addons/hakoniwa_msgs` は platform 非依存だが、通常は runtime addon と同梱してよい
- `addons/hakoniwa` の native binary は platform 混在で配らない

Windows 対応範囲の補足:

- `addons/hakoniwa_msgs`
  - GDScript だけなので platform 非依存
  - Windows 追加対応は基本不要
- codec plugin
  - `<package>_codec.gdextension` は template で Windows `.dll` entry を持つ
  - artifact に `.dll` と `.gdextension` を同梱すればよい
- runtime addon
  - `hakoniwa.gdextension` は Windows `.dll` entry を持つようにした
  - ただし Windows 実機での build / load 確認は未実施

staging 内容を確認したい場合:

```bash
bash tools/addon_artifact_tool.sh paths --platform macos --arch arm64
```

この手順で収集されるもの:

- `addons/hakoniwa/bin/*.dylib`
- `addons/hakoniwa/codecs/*.dylib`
- `addons/hakoniwa/codecs/*.gdextension`
- `addons/hakoniwa/plugin.cfg`
- `addons/hakoniwa/hakoniwa.gdextension`
- `addons/hakoniwa/scripts/`
- `addons/hakoniwa_msgs/` が存在する場合はそれも同梱

codec plugin を package 指定で生成したい場合:

```bash
bash tools/codec_plugin_tool.sh list
bash tools/codec_plugin_tool.sh configure --packages "hako_msgs;std_msgs"
bash tools/codec_plugin_tool.sh build
```

custom codec を含める場合の基本手順:

1. `tools/codec_plugin_tool.sh configure --packages "<package>"` を実行する
2. `tools/codec_plugin_tool.sh build` を実行する
3. 以下が両方生成されていることを確認する

- `addons/hakoniwa/codecs/<package>_codec.<shared-library>`
- `addons/hakoniwa/codecs/<package>_codec.gdextension`

4. typed GDScript class が必要なら `tools/message_addon_tool.sh sync --packages "<package>"` を実行する
5. まず `examples/basic_subscriber` 相当の endpoint-only 動作確認を行う
6. その後に `HakoniwaSimNode` や `hakoniwa-core-pro` 統合へ進む

generated GDScript message class を `addons/hakoniwa_msgs` へ同期する場合:

```bash
bash tools/message_addon_tool.sh list
bash tools/message_addon_tool.sh sync --packages all
```

`codec_plugin_tool.sh` の主な引数:

- `list`
  - 利用可能な codec package 一覧を表示する
- `configure`
  - `--build-dir DIR`: build directory を指定する
  - `--packages PKG1;PKG2|all`: build 対象 package を指定する
  - `--godot-bin PATH`: smoke test 用 Godot 実行ファイルを指定する
  - `--tests ON|OFF`: CTest を有効化するかを指定する
- `build`
  - `--build-dir DIR`: build directory を指定する
  - `--target TARGET`: 特定 target だけ build する
- `test`
  - `--build-dir DIR`: build directory を指定する
- `paths`
  - `--build-dir DIR`: build directory を指定する
  - `--packages PKG1;PKG2|all`: 生成物の確認対象 package を指定する

`addon_artifact_tool.sh` の主な引数:

- `stage`
  - `--platform macos|linux|windows`: 対象 platform を指定する
  - `--arch ARCH`: architecture を指定する
  - `--dist-dir DIR`: 出力先 directory を指定する
  - `--runtime-dir DIR`: runtime addon の入力元を指定する
  - `--msgs-dir DIR`: message addon の入力元を指定する
  - `--packages PKG1;PKG2|all`: 同梱する codec package を指定する
- `archive`
  - `stage` と同じ引数で archive を作る
  - `macOS / Linux` は `.tar.gz`
  - `Windows` は `.zip`

`addon_artifact_tool.ps1` の位置づけ:

- Windows の正式導線として使う
- `stage` / `archive` / `paths` を持つ
- `stage` と `paths` は他 platform 引数でも呼べるが、`archive` は実質 Windows 用と考える
- macOS / Linux では引き続き `addon_artifact_tool.sh` を使う
- `paths`
  - staging path と archive path を表示する

`message_addon_tool.sh` の主な引数:

- `list`
  - 利用可能な generated GDScript message package 一覧を表示する
- `sync`
  - `--packages PKG1;PKG2|all`: 同期する package を指定する
  - `--target-dir DIR`: 出力先を指定する
- `paths`
  - `--packages PKG1;PKG2|all`: 確認対象 package を指定する
  - `--target-dir DIR`: 出力先を指定する

package 指定ルール:

- 複数 package は `;` 区切りで指定する
- 全 package を対象にする場合は `all` を指定する

例:

```bash
bash tools/codec_plugin_tool.sh configure --packages "hako_msgs;std_msgs;geometry_msgs"
bash tools/codec_plugin_tool.sh configure --packages all
bash tools/addon_artifact_tool.sh stage --platform macos --arch arm64 --packages all
```

生成物の確認:

```bash
bash tools/codec_plugin_tool.sh paths --packages "hako_msgs;std_msgs"
```

## 生成ファイルの扱い

codec plugin の package ごとの C++ source は、repo 直下には置かず、CMake configure 時に `build/` 配下へ生成する。

代表例:

- `build/native/generated/hako_msgs/hako_msgs_codec_plugin.cpp`
- `build/native/generated/hako_msgs/hako_msgs_codec_plugin_init.cpp`

これらは一時生成物だが、build directory を消すまでは残る。

つまり:

- configure のたびに上書きされる
- `build/` を削除すると消える
- Git 管理対象にはしない

addon 側の出力物は別で、以下に置かれる。

- `addons/hakoniwa/codecs/<package>_codec.<shared-library>`
- `addons/hakoniwa/codecs/<package>_codec.gdextension`
- `addons/hakoniwa_msgs/<package>/*.gd`

`addons/hakoniwa_msgs` の `.gd` は `hakoniwa-pdu-registry` の generated script を同期したものであり、sync 時に Godot 4.6 で利用しやすい形へ正規化する。

## 可変長データの注意

固定長型は比較的素直に `pdu_size` を決められるが、可変長型は同じではない。

- `std_msgs/UInt64` や `geometry_msgs/Pose` は、`hakoniwa-pdu-registry` の型サイズ情報を基準にし、基本は `型サイズ + 24 bytes` で見積もる
- `std_msgs/UInt64MultiArray` はヒープ領域に実データを持つ

そのため、可変長型の `pdu_size` は `registry の型サイズ + 24 bytes` を出発点にしつつ、実データ長に応じてヒープ領域ぶんを追加して設定する必要がある。

## 動作確認

M1 時点では、サンプルプロジェクトで GDExtension が読み込まれ、native 側から `hakoniwa-pdu-endpoint` に触れるところまで確認対象とする。

headless 実行例:

```bash
/Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path examples/basic_subscriber --quit
```

期待する出力:

```text
hakoniwa-pdu-endpoint
true
```

現在の sample では、以下の型を確認対象にしている。

- 単純型: `std_msgs/UInt64`
- 複雑型: `geometry_msgs/Pose`
- 可変長配列: `std_msgs/UInt64MultiArray`

追加で、`geometry_msgs/Twist` による `motor` / `pos` の endpoint-only typed send / recv も確認済みである。

## codec plugin 利用時の注意

通常利用では、codec plugin path は拡張子なしで指定する。

例:

```gdscript
endpoint.codec_plugins = PackedStringArray([
    "res://addons/hakoniwa/codecs/geometry_msgs_codec"
])
```

`HakoniwaEndpointNode` と `HakoniwaSimNode` は、内部で対応する `.gdextension` resource のロードを吸収する。

一方で `HakoniwaCodecRegistry` を直接使う low-level 利用では、先に対応する `.gdextension` を `load()` してから plugin を使うこと。

詳細は [troubleshooting.md](/Users/tmori/project/oss/hakoniwa-godot/docs/troubleshooting.md) を参照。
