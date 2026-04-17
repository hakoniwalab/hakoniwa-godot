# Architecture

## 目的

`hakoniwa-godot` は、Godot を箱庭接続ノードとして利用するための統合パッケージです。

ただし初期フェーズでは、まず `hakoniwa-pdu-endpoint` を完成させ、その後に `hakoniwa-core-pro` の時間同期を統合する段階構成を採ります。

## 初期アーキテクチャ

```text
hakoniwa-godot/
├─ addons/
│  └─ hakoniwa/
│     ├─ plugin.cfg
│     ├─ gdextension/
│     ├─ scripts/
│     └─ icons/
├─ native/
│  ├─ src/
│  ├─ include/
│  └─ CMakeLists.txt
├─ third_party/
│  └─ hakoniwa-pdu-endpoint/
├─ examples/
│  └─ basic_subscriber/
├─ docs/
└─ README.md
```

## レイヤ分割

### 1. Time Sync Layer

C++ で `hakoniwa-core-pro` の polling asset API をラップし、Godot を時間同期付き asset として登録する層です。

責務:

- asset の初期化と register
- start / stop / reset event の取得
- world time の取得
- asset simtime の通知
- Godot loop と Hakoniwa simtime の橋渡し

初期方針:

- Godot は polling asset として参加する
- conductor / master は外部プロセスが持つ
- callback API ではなく polling API を使う

### 2. Endpoint Runtime Layer

C++ で `hakoniwa-pdu-endpoint` をラップし、GDExtension 経由で Godot に公開する層です。

責務:

- endpoint の生成と破棄
- 接続設定の保持
- PDU 受信処理
- `latest` / `queue` モードの実装
- `PackedByteArray` ベースの raw payload 受け渡し

### 3. Godot Wrapper Layer

GDScript または Godot の公開クラスで、利用者に対する使いやすい API を提供する層です。

責務:

- 利用者向けクラスの提供
- Node ライフサイクルとの統合
- signal や helper API の提供
- time sync node と endpoint node の接続

### 4. Codec Plugin Layer

PDU binary と Godot の値表現を相互変換する層です。

この層は `hakoniwa-pdu-registry` の生成物を利用し、message package ごとの shared library plugin として提供することを想定します。

責務:

- `PackedByteArray -> Dictionary / Array / Packed*Array`
- `Dictionary / Array / Packed*Array -> PackedByteArray`
- package / message ごとの converter 提供
- plugin 単位での選択的導入

設計方針:

- plugin 境界は C ABI とする
- platform ごとの差分は loader 層で吸収する
- macOS は `.dylib`
- Linux は `.so`
- Windows は `.dll`

### 5. Typed Message Layer

生成済み `GDScript` typed classes により、利用者にとって扱いやすい型 API を提供する層です。

この層も `hakoniwa-pdu-registry` の生成物を利用する。

責務:

- typed member を持つ message class の提供
- `from_dict()` / `to_dict()` による Godot 値表現との変換
- 利用者コードでの可読性向上

### 6. Example Layer

最小の導入例と検証例を提供する層です。

## M1 で確定した構成

```text
hakoniwa-godot/
├─ addons/hakoniwa/                 # 配布単位
├─ native/                          # GDExtension 実装
├─ third_party/godot-cpp/           # Godot C++ bindings
├─ third_party/hakoniwa-core-pro/
├─ third_party/hakoniwa-pdu-endpoint/
├─ tests/smoke/basic_subscriber/    # endpoint / codec smoke test 用 Godot project
└─ docs/
```

## 依存方針

- `godot-cpp` は Git submodule で固定する
- `hakoniwa-core-pro` は Git submodule で固定する
- `hakoniwa-pdu-endpoint` も Git submodule で固定する
- M1 では追加のネットワーク依存を避けるため、optional transports は無効にする
- `hakoniwa-pdu-endpoint` との接続はまず C API ベースで始める

## message layer の将来方針

`hakoniwa-pdu-registry` には、以下の Godot 向け生成物が既に存在する。

- `pdu/godot_cpp_runtime/`
- `pdu/godot_cpp/<pkg>/`
- `pdu/godot_gd/<pkg>/`

そのため、`hakoniwa-godot` はこれらを本体へ全同梱するのではなく、以下の分離構成を目指す。

- 本体: endpoint runtime
- plugin: package ごとの codec shared library
- script: `addons/hakoniwa_msgs` に置く package ごとの typed GDScript message classes

## plugin loading 方針

package ごとの codec shared library は、platform ごとの loader 実装を通じて動的ロードする。

想定:

- 共通 interface は C ABI
- macOS / Linux は `dlopen` 系
- Windows は `LoadLibrary` 系
- loader 利用側は platform 差分を意識しない

plugin 未導入時は、raw `PackedByteArray` API に fallback する。

## 配布アーキテクチャ

`addons/hakoniwa` は論理的には 1 つの addon だが、native binary を含むため配布 artifact は platform ごとに分かれる。

考えるべき軸:

- OS
- architecture
- build type

特に codec plugin layer が入ったことで、以下の両方が platform 依存になった。

- endpoint runtime binary
- package ごとの codec shared library

したがって、最終的な配布は `addons/hakoniwa` の source 構造を保ちながら、platform ごとに別 artifact を生成する方針になる。

一方、typed message layer は platform 非依存なので、`addons/hakoniwa_msgs` として独立配置する。

## M1 の実装境界

M1 では、GDExtension クラス `HakoniwaPduEndpoint` を登録し、native 側から `hakoniwa-pdu-endpoint` にリンクできることだけを確認対象にした。

この段階では、実際の endpoint 設定や `latest` / `queue` の利用 API はまだ未実装である。

## 初期方針

- まずは受信専用に限定する
- API は最小限から始める
- 利用者の導線を優先して `addons/` 配布を前提に考える
- データ表現は初期段階では `Dictionary` ベースを優先する
- 型付き decode は本体から分離して段階的に導入する

## 今後の拡張

将来的には以下を統合対象に含める。

- `hakoniwa-core-pro` による時間同期
- `hakoniwa-pdu-rpc` による操作 API
- 型付きメッセージクラス
- package ごとの codec plugin
- エディタプラグイン支援

時間同期の詳細方針は [core_pro_design.md](core_pro_design.md) に切り出す。
