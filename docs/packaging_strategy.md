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
├─ scripts/
└─ LICENSES/
```

## 配布物に含めるもの

- GDExtension 定義
- 各プラットフォーム向けネイティブバイナリ
- Godot 用ラッパスクリプト
- 最小サンプルへのリンク
- 導入ドキュメント

## 開発時の構成と配布時の構成

開発時は `native/`, `third_party/`, `examples/` を含んだリポジトリ構成で管理する。

利用者向けには、最終的に以下のどちらかを選ぶ。

1. リポジトリをそのまま clone して使う
2. `addons/hakoniwa` を切り出して使う

初期段階では、まず 1 を成立させ、その後 2 に拡張する。

## 対応方針

- まずは開発環境でのビルド成功を優先する
- 次にサンプル込みでの導入成功を優先する
- その後に配布バイナリ整備へ進む

## M1 での採用

M1 では以下を採用した。

- 配布単位: `addons/hakoniwa`
- ネイティブ実装: `native/`
- 動作確認プロジェクト: `examples/basic_subscriber`
- 依存管理: `third_party/` の Git submodule

## 未決定事項

- 対応 Godot バージョン
- 対応 OS とアーキテクチャ
- CI でバイナリ生成まで行うか
- ライセンス表記の同梱方針
