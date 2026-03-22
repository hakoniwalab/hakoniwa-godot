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

ただし、現時点で具体的な作成手順を文書化しているのは macOS 向けである。
まずは `macOS arm64` 向け artifact を基準に扱う。

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
  - `--platform macos|linux`: 対象 platform を指定する
  - `--arch ARCH`: architecture を指定する
  - `--dist-dir DIR`: 出力先 directory を指定する
  - `--runtime-dir DIR`: runtime addon の入力元を指定する
  - `--msgs-dir DIR`: message addon の入力元を指定する
  - `--packages PKG1;PKG2|all`: 同梱する codec package を指定する
- `archive`
  - `stage` と同じ引数で `.tar.gz` まで作る
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
