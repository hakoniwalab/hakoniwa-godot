# Codec Plugin Design

## 目的

`hakoniwa-godot` 本体に全 message package を同梱せず、package ごとの codec plugin を shared library として追加できるようにする。

初期実装では、plugin export 名と loader を先に固定し、message converter の追加単位を package ごとにそろえる。

## 役割分担

- `hakoniwa-godot` 本体
  - endpoint runtime
  - plugin loader
  - codec registry
  - plugin 未導入時の raw `PackedByteArray` fallback
- codec plugin
  - package 名の宣言
  - message ごとの decode / encode 関数の提供
- `hakoniwa-pdu-registry` 生成物
  - `PackedByteArray <-> Dictionary` converter 実装

## phase-1 ABI

plugin export は C ABI に固定する。

```c
const CodecPluginV1* hako_godot_codec_get_plugin_v1(void);
```

ただし phase-1 では、個々の converter callback は Godot 型ベースの C++ 関数ポインタとする。

理由:

- `hakoniwa-pdu-registry` の `pdu/godot_cpp/<pkg>/` 生成物と直接つなぎやすい
- `PackedByteArray <-> Dictionary` の責務を崩さない
- plugin loader の設計を先に固定できる

制約:

- callback ABI 自体は toolchain 間の完全な独立 ABI ではない
- Windows を含む厳密な配布形態では、将来 pure C bridge へ置き換える可能性がある

## platform loader

shared library のロードは platform ごとに分ける。

- macOS / Linux: `dlopen`, `dlsym`, `dlclose`
- Windows: `LoadLibrary`, `GetProcAddress`, `FreeLibrary`

利用側は `SharedLibrary` を通して差分を意識しない。

## package plugin の例

plugin 実装は手書きではなく、`hakoniwa-pdu-registry/pdu/godot_cpp/<pkg>/pdu_conv_*.hpp` から package 単位で生成する。

生成される plugin は、以下を固定するための雛形である。

- package 名の宣言方法
- message entry の並べ方
- export symbol 名
- generated converter の束ね方

## build 方針

`native/CMakeLists.txt` では、`pdu/godot_cpp/` 配下の package directory を列挙し、各 package について:

- codec plugin source
- codec plugin init source
- `.gdextension` resource

を生成する。

出力単位:

- `addons/hakoniwa/codecs/<package>_codec.<shared-library>`
- `addons/hakoniwa/codecs/<package>_codec.gdextension`

中間生成物:

- `build/native/generated/<package>/<package>_codec_plugin.cpp`
- `build/native/generated/<package>/<package>_codec_plugin_init.cpp`

これらの generated source は CMake configure/build の生成物であり、build directory が残る限り保持される。

扱い:

- build directory を削除すると消える
- 再configure 時に上書きされる
- Git 管理には含めない

## 補助ツール

`tools/codec_plugin_tool.sh` は codec plugin 用の補助 CLI である。

主な用途:

- package 一覧を確認する
- package 指定で CMake configure する
- 特定 plugin target を build する
- 生成物パスを確認する

このツール自体は plugin の手書き source を作るものではなく、CMake による package plugin 生成の入口をまとめたものと位置づける。

## 次に詰めること

- plugin の配置規則
- package discovery 方法
- Godot 側から registry を呼ぶ公開 API
- phase-2 で pure C bridge へ広げるかどうか
