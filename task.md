# Task

## 方針

最初のマイルストーンは、`hakoniwa-pdu-endpoint` を Godot から利用できる最小パッケージを完成させることです。

## マイルストーン

### M1. 土台作成

- [x] ディレクトリ構成を確定する
- [x] 開発用 Godot プロジェクト雛形を作る
- [x] `native/` GDExtension 雛形を作る
- [x] `third_party/` の依存取り込み方針を決める
- [x] CMake ビルドを通す

### M2. endpoint 接続

- [x] `hakoniwa-pdu-endpoint` を native 側へ組み込む
- [x] Godot から endpoint を生成できるようにする
- [x] 接続設定 API を定義する
- [x] 受信開始 / 停止 API を定義する

### M3. データ受信 API

- [x] `latest` モードを実装する
- [x] `queue` モードを実装する
- [x] Godot への返却形式を確定する
- [x] エラー時の扱いを定義する

### M4. 利用者向け整備

- [x] 最小サンプルシーンを作る
- [ ] 導入手順を README に反映する
- [ ] `docs/` に設計と利用手順を残す
- [ ] 最低限の検証手順を文書化する
- [x] API 全体像を整理する
- [x] API リファレンスを整備する
- [x] API 利用シーケンスを整理する

## 直近タスク

### 1. リポジトリ骨格の決定

- [x] 必要ディレクトリを作る
- [x] 配布単位を `addons/hakoniwa` ベースにする
- [x] examples は `examples/basic_subscriber` で分離する

### 2. API 設計の確定

- [x] Godot 側の公開クラス名を決める
- [x] Node と Resource のどちらを中心にするか決める
- [x] 受信 API を poll ベースにするか signal 併用にするか決める
- [x] 設定 API と状態遷移を定義する
- [x] ドキュメントに出す最小 API セットを定める

### 4. 次に詰める実装

- [x] `queue` モード用の config とサンプルを追加する
- [x] `recv_next()` ベースの利用例を example で確認する
- [x] `set_recv_event()` の利用パスを example で確認する
- [x] `send_by_name()` を API ドキュメントへ正式反映する
- [ ] Godot 側の typed wrapper を用意するか判断する

### 3. 実装開始条件の明確化

- [x] 対応 Godot バージョンを決める
- [x] 対応 OS を決める
- [x] 依存ライブラリの取り込み方を決める

## 進め方

作業は以下の順で進める。

1. 設計を `docs/` に固定する
2. 最小構成のディレクトリを作る
3. GDExtension をビルド可能にする
4. endpoint の最小受信を通す
5. examples と README を仕上げる

## 完了条件

以下を満たしたら、最初の目標は達成です。

- 第三者が clone してビルドできる
- Godot 上で PDU を受信して表示できる
- `latest` / `queue` の使い分けが分かる
- README と docs で導入判断ができる
- API の入口、仕様、利用順序が docs で追える
