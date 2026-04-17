# Packaging Strategy

## 目的

`hakoniwa-godot` を、第三者が Godot プロジェクトに取り込める形で配布する。

## 基本方針

初期フェーズでは、Godot 利用者にとって導入が分かりやすい構成を優先する。

そのため、配布単位は `addons/hakoniwa` を中心に検討する。

## 想定構成

```text
addons/hakoniwa/
├─ plugin.cfg
├─ hakoniwa.gdextension
├─ bin/
├─ codecs/
├─ scripts/
└─ LICENSES/
```

## 配布物に含めるもの

- GDExtension 定義
- 各プラットフォーム向けネイティブバイナリ
- package ごとの codec shared library
- package ごとの codec `.gdextension`
- Godot 用ラッパスクリプト
- platform 非依存の共通 GDScript
- 最小サンプルへのリンク
- 導入ドキュメント

## addon と配布 artifact の違い

`addons/hakoniwa` は Godot から見た論理的な addon 単位である。

ただしこの addon は native binary を含むため、配布 artifact としては OS / architecture ごとに分ける必要がある。

具体例:

- macOS arm64 addon artifact
- macOS x86_64 addon artifact
- Ubuntu x86_64 addon artifact
- Windows x86_64 addon artifact

つまり、論理的には 1 addon だが、配布物としては複数になる。

さらに重要なのは、`addons/` 配下は repo の正本ではなく、配布成果物として扱う点である。

正本は以下に置く。

- `native/`
- `third_party/`
- `docs/`
- `tools/`
- CMake 設定

`addons/hakoniwa` と `addons/hakoniwa_msgs` は、source から生成または収集して配布する対象とする。

## platform 非依存ファイル

以下は platform 非依存として扱う。

- `plugin.cfg`
- `scripts/`
- 将来の generated GDScript message classes
- ドキュメントと補助リソース

これらは native binary と分離してもよいし、binary addon artifact に同梱してもよい。

generated GDScript message classes の配置先は `addons/hakoniwa_msgs/` とする。

役割分担:

- `addons/hakoniwa`
  - endpoint runtime
  - codec plugin loader
  - platform 依存 binary
- `addons/hakoniwa_msgs`
  - platform 非依存の generated GDScript message classes

## platform ごとの差分

native binary は platform ごとに異なる。

- macOS: `.dylib`
- Linux / Ubuntu: `.so`
- Windows: `.dll`

この差分は以下の両方に現れる。

- `addons/hakoniwa/bin/` の本体 GDExtension library
- `addons/hakoniwa/codecs/` の package ごとの codec plugin

そのため、`addons/hakoniwa` を zip などで配布する場合は、platform 混在ではなく platform 別に切る。

## 当面の配布方針

初期段階では、以下を正本とする。

1. source 配布
2. 利用者が対象 platform 上で build

その後、必要に応じて以下へ拡張する。

1. CI で platform ごとの binary addon artifact を生成
2. release asset として配布

この方針では、repo には addon 生成方法と配布方法を残し、addon 自体を正本として Git 管理しない。

配布成果物の作成は、当面 `tools/addon_artifact_tool.sh` で行う。

現時点で具体的な作成手順を先に固める対象は `macOS arm64` とする。
Linux / Ubuntu 向けも同じ tool で扱える設計だが、ドキュメント上の基準手順はまず macOS で定義する。

## codec plugin の配布単位

codec plugin は message package ごとの shared library とする。

例:

- `hako_msgs_codec`
- `std_msgs_codec`
- `geometry_msgs_codec`

各 plugin は platform ごとに拡張子だけが変わる。

したがって package 単位と platform 単位の 2 軸で配布を考える必要がある。

## common codecs

現時点で build 実績のある package 群は `common codecs` として扱う。

対象:

- `builtin_interfaces`
- `can_msgs`
- `drone_srv_msgs`
- `ev3_msgs`
- `geometry_msgs`
- `hako_mavlink2_msgs`
- `hako_mavlink_msgs`
- `hako_msgs`
- `hako_srv_msgs`
- `mavros_msgs`
- `nav_msgs`
- `sensor_msgs`
- `std_msgs`
- `tf2_msgs`

当面の方針:

- official artifact では `common codecs` を同梱対象とする
- source build では `common codecs` の一部だけを選んで build することもできる
- 将来 additional codecs を別配布にする余地は残す

## 想定 artifact 例

macOS arm64 向け:

```text
addons/hakoniwa/
├─ hakoniwa.gdextension
├─ bin/
│  └─ libhakoniwa_godot_native.dylib
└─ codecs/
   ├─ hako_msgs_codec.dylib
   ├─ hako_msgs_codec.gdextension
   ├─ std_msgs_codec.dylib
   └─ std_msgs_codec.gdextension

addons/hakoniwa_msgs/
└─ ...
```

この artifact は次のコマンドで作る。

```bash
bash tools/addon_artifact_tool.sh stage --platform macos --arch arm64 --packages all
bash tools/addon_artifact_tool.sh archive --platform macos --arch arm64 --packages all
```

出力先:

```text
dist/hakoniwa-godot-macos-arm64/
dist/hakoniwa-godot-macos-arm64.tar.gz
```

Windows x86_64 向け:

```text
addons/hakoniwa/
├─ hakoniwa.gdextension
├─ bin/
│  └─ hakoniwa_godot_native.dll
└─ codecs/
   ├─ hako_msgs_codec.dll
   ├─ hako_msgs_codec.gdextension
   ├─ std_msgs_codec.dll
   └─ std_msgs_codec.gdextension

addons/hakoniwa_msgs/
└─ ...
```

## official artifact 方針

当面の official artifact は、以下の考え方でまとめる。

- artifact 単位は `OS + architecture`
- native binary と codec plugin はその platform 向けを同梱
- `addons/hakoniwa_msgs` は platform 非依存層として同梱
- codec plugin は `common codecs` を標準同梱
- source build は引き続き正本とする

初期の対応対象:

- macOS arm64

次段階:

- Ubuntu / Linux

同じ packaging tool で両方を扱い、platform ごとの差分は shared library 拡張子と artifact 名に閉じ込める。

## 開発時の構成と配布時の構成

開発時は `native/`, `third_party/`, `examples/` を含んだリポジトリ構成で管理する。

利用者向けには、最終的に以下のどちらかを選ぶ。

1. リポジトリをそのまま clone して使う
2. `addons/hakoniwa` と `addons/hakoniwa_msgs` を切り出して使う

初期段階では、まず 1 を成立させ、その後 2 に拡張する。

## 対応方針

- まずは開発環境でのビルド成功を優先する
- 次にサンプル込みでの導入成功を優先する
- その後に配布バイナリ整備へ進む

## M1 での採用

M1 では以下を採用した。

- 配布単位: `addons/hakoniwa`
- ネイティブ実装: `native/`
- 動作確認プロジェクト: `tests/smoke/basic_subscriber`
- 依存管理: `third_party/` の Git submodule

## 未決定事項

- 対応 OS / architecture ごとの配布優先順位
- `arm64` / `x86_64` の命名規則
- CI でバイナリ生成まで行うか
- ライセンス表記の同梱方針
