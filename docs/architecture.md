# Architecture

## 目的

`hakoniwa-godot` は、Godot を箱庭接続ノードとして利用するための統合パッケージです。

ただし初期フェーズでは、対象を `hakoniwa-pdu-endpoint` のみに絞り、状態受信の成立を最優先にします。

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

### 1. Native Layer

C++ で `hakoniwa-pdu-endpoint` をラップし、GDExtension 経由で Godot に公開する層です。

責務:

- endpoint の生成と破棄
- 接続設定の保持
- PDU 受信処理
- `latest` / `queue` モードの実装
- Godot へ返せる値への変換

### 2. Godot Wrapper Layer

GDScript または Godot の公開クラスで、利用者に対する使いやすい API を提供する層です。

責務:

- 利用者向けクラスの提供
- Node ライフサイクルとの統合
- signal や helper API の提供

### 3. Example Layer

最小の導入例と検証例を提供する層です。

## M1 で確定した構成

```text
hakoniwa-godot/
├─ addons/hakoniwa/                 # 配布単位
├─ native/                          # GDExtension 実装
├─ third_party/godot-cpp/           # Godot C++ bindings
├─ third_party/hakoniwa-pdu-endpoint/
├─ examples/basic_subscriber/       # 動作確認用 Godot project
└─ docs/
```

## 依存方針

- `godot-cpp` は Git submodule で固定する
- `hakoniwa-pdu-endpoint` も Git submodule で固定する
- M1 では追加のネットワーク依存を避けるため、optional transports は無効にする
- `hakoniwa-pdu-endpoint` との接続はまず C API ベースで始める

## M1 の実装境界

M1 では、GDExtension クラス `HakoniwaPduEndpoint` を登録し、native 側から `hakoniwa-pdu-endpoint` にリンクできることだけを確認対象にした。

この段階では、実際の endpoint 設定や `latest` / `queue` の利用 API はまだ未実装である。

## 初期方針

- まずは受信専用に限定する
- API は最小限から始める
- 利用者の導線を優先して `addons/` 配布を前提に考える
- データ表現は初期段階では `Dictionary` ベースを優先する

## 今後の拡張

将来的には以下を統合対象に含める。

- `hakoniwa-core-pro` による時間同期
- `hakoniwa-pdu-rpc` による操作 API
- 型付きメッセージクラス
- エディタプラグイン支援
