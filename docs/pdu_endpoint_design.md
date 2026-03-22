# PDU Endpoint Design

## 目的

`hakoniwa-pdu-endpoint` を Godot から利用できるようにし、外部シミュレーションの状態を受信できるようにする。

## ユースケース

### 1. 可視化用途

毎フレーム、対象オブジェクトの最新状態だけを取得したい。

この場合は `latest` モードを使う。

### 2. イベント処理用途

到着した全イベントを順番に処理したい。

この場合は `queue` モードを使う。

## 公開 API の初期案

Node ベースで開始する。

候補クラス:

- `HakoniwaPduEndpoint`

基本単位:

```text
1 Node = 1 native endpoint handle
```

想定メソッド:

```text
open(config_path: String) -> int
close() -> void
start() -> int
post_start() -> int
stop() -> void
process_recv_events() -> void
recv_by_name(robot: String, pdu_name: String) -> Dictionary
recv_next() -> Dictionary
set_recv_event(robot: String, channel_id: int) -> int
get_pending_count() -> int
is_running() -> bool
```

## M1 で入れた最小 API

M1 では GDExtension の足場確認を優先し、以下の最小 API だけを実装した。

```text
get_backend_name() -> String
probe_native_backend() -> bool
```

これは `hakoniwa-pdu-endpoint` へのリンクと、Godot 上でのクラス登録を検証するための暫定 API である。

## 戻り値方針

初期実装では Godot の扱いやすさを優先し、受信データは `Dictionary` または `Array[Dictionary]` 相当で返す。

例:

```text
{
  "key": "/drone/pose",
  "timestamp": 12345678,
  "payload": PackedByteArray(...)
}
```

## 今回の区切り

今回のマイルストーンでは、基盤 API としては `payload` を `PackedByteArray` のまま扱う。

その上で、codec plugin と generated GDScript message class を組み合わせることで、Godot 利用者には `Dictionary` と typed object まで提供する。

この段階で保証するのは以下まで。

- Godot から endpoint を開ける
- バイナリ payload を送れる
- バイナリ payload を受け取れる
- `latest` / `queue` の意味の違いを Godot から使える
- `Dictionary` に decode できる
- `HakoniwaTypedEndpoint` で typed object を送受信できる

## 今回の対象外

以下は次の段階の課題として扱う。

- codec plugin / message addon の自動 discovery
- `hakoniwa-core-pro` の時間同期統合
- `hakoniwa-pdu-rpc` の操作系統合

## モード設計

### latest

- キーごとに最新値だけ保持する
- `_process()` と相性が良い
- 可視化用途を主対象とする

### queue

- 到着順にイベントを保持する
- `_physics_process()` や制御処理と相性が良い
- 取りこぼしを避けたい処理を主対象とする

## スレッド方針

初期段階では、スレッド導入は慎重に扱う。

候補は 2 つある。

1. Godot 側から明示的に poll する
2. Native 側で受信スレッドを持ち、内部バッファに積む

まずは単純性を優先し、poll 中心の設計を基本案とする。

Godot 側では、main loop から caller-controlled に受信を進める。

callback は補助機能として扱い、scene tree 更新の主経路にはしない。

## エラーハンドリング方針

- 接続失敗は戻り値または `get_last_error()` 相当で参照できるようにする
- データ未到着は例外ではなく空結果で表現する
- 無効な設定値は起動前に検出する

## 可変長データの扱い

固定長型と可変長型では `pdu_size` の考え方が異なる。

- `std_msgs/UInt64` や `geometry_msgs/Pose` のような固定長型は、`hakoniwa-pdu-registry` の型サイズ情報を基準にし、基本は `型サイズ + 24 bytes` で考える
- `std_msgs/UInt64MultiArray` のような可変長型は、ヒープ領域に実データを展開するため、`pdu_size` に余裕が必要になる

そのため、可変長型の example では `registry の型サイズ + 24 bytes` を出発点にしつつ、さらにヒープ領域ぶんを加えた十分大きい `pdu_size` を設定して動作確認する。

## 未決定事項

- config の必須項目
- ペイロードをそのまま bytes で返すか、デコード層を持つか
- signal をどこまで提供するか
- Node 上の property と method の責務分担
