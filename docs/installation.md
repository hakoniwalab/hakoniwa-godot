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
cmake -S . -B build
cmake --build build -j4
```

ビルド成果物:

- `addons/hakoniwa/bin/libhakoniwa_godot_native.dylib`

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
