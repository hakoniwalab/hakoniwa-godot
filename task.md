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
- [x] 導入手順を README に反映する
- [x] `docs/` に設計と利用手順を残す
- [x] 最低限の検証手順を文書化する
- [x] API 全体像を整理する
- [x] API リファレンスを整備する
- [x] API 利用シーケンスを整理する

### M5. codec plugin 基盤

- [x] `HakoniwaCodecRegistry` を追加する
- [x] codec plugin ABI と loader の骨格を追加する
- [x] `hako_msgs` codec plugin の smoke test を通す
- [x] package ごとの shared library plugin 生成基盤を追加する
- [x] package ごとの typed GDScript message 配布方針を固める

### M6. GDScript message / typed endpoint

- [x] `addons/hakoniwa_msgs` 生成導線を追加する
- [x] `HakoniwaEndpointNode` を追加する
- [x] `HakoniwaTypedEndpoint` を追加する
- [x] `get_typed_endpoint(robot, pdu_name)` を追加する
- [x] 単純型の typed endpoint 動作確認を行う
- [x] 複雑型の typed endpoint 動作確認を行う
- [x] 可変長配列の typed endpoint 動作確認を行う

### M7. 時間同期 / 操作系

- [x] `hakoniwa-core-pro` の時間同期モデルを設計する
- [x] Godot 側の時間制御 API を定義する
- [x] 最初のテスト方針を定義する
- [x] `hakoniwa-core-pro` の単体テスト設計を起こす
- [x] `hakoniwa-core-pro` polling C API の native wrapper を追加する
- [x] thin GDScript bridge を追加する
- [x] `HakoniwaSimNode` の最小骨格を実装する
- [x] conductor 付き lifecycle smoke を通す
- [x] reset 後の再 start lifecycle smoke を通す
- [ ] Godot + Python の 2 アセット統合テストを設計する
- [ ] 最小の時間同期 sample を通す
- [ ] `hakoniwa-pdu-rpc` の操作系 API を設計する
- [ ] 最小の RPC sample を通す

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
- [x] Godot 側の typed wrapper を用意するか判断する
- [x] package ごとの typed GDScript を addons へどう配布するか決める
- [x] `message_addon_tool.sh` を追加する
- [x] `example` を wrapper / typed endpoint ベースへ更新する
- [x] 可変長配列の `pdu_size` 注意点を整理する
- [ ] codec plugin auto-discovery を入れるか判断する
- [x] `hakoniwa-core-pro` 統合の docs を起こす
- [x] `hakoniwa-core-pro` のユーザインタフェースを設計する
- [x] `hakoniwa-core-pro` の内部インタフェース 1 段目を実装する
- [ ] `issue-physics.md` に基づき Godot physics 停止方式を調査する
- [ ] physics 停止時に `_physics_process()` / `_process()` がどう振る舞うかを確認する
- [ ] UI を止めずに simulation だけ止める構成を検証する
- [ ] UI root / monitor node に `process_mode = Always` が必要であることをマニュアルへ追記する
- [ ] physics 連携時の state model (`BLOCKED_BY_WORLD_TIME` など) を設計へ反映する
- [ ] `hakoniwa-pdu-rpc` 統合の docs を起こす

### 5. WebSocket endpoint-only example

- [ ] `HakoniwaEndpointNode` だけを使う Godot sample を追加する
- [ ] SimNode / 時刻同期を使わない構成にする
- [ ] Godot 側 config を WebSocket client/server のどちらかで固定する
- [ ] Python 側 sample を `hakoniwa-pdu-endpoint` `Endpoint` ベースで追加する
- [ ] `python_pdu_minimal` と同じ `geometry_msgs/Twist` の送受信内容に揃える
- [ ] Godot 側で `open() / start() / post_start()` と subscription の最小導線を確認する
- [ ] Python 側で `send_by_name()` / `subscribe_on_recv_callback_by_name()` の最小導線を確認する
- [ ] example 用 config を `examples/` 配下に置く
- [ ] example README に起動順と成功時ログを書く
- [ ] `SimNode` なし導線として `docs/quick_start.md` か関連 doc から辿れるようにする

### 3. 実装開始条件の明確化

- [x] 対応 Godot バージョンを決める
- [x] 対応 OS を決める
- [x] 依存ライブラリの取り込み方を決める
- [x] codec plugin の shared library 方針を決める

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
- Godot 上で PDU を raw / decoded / typed object として受信できる
- `latest` / `queue` の使い分けが分かる
- README と docs で導入判断ができる
- API の入口、仕様、利用順序が docs で追える
