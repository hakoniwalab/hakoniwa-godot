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

想定メソッド:

```text
configure(config: Dictionary) -> void
start() -> int
stop() -> void
poll_latest(key: String = "") -> Variant
poll_next() -> Variant
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

## エラーハンドリング方針

- 接続失敗は戻り値または `get_last_error()` 相当で参照できるようにする
- データ未到着は例外ではなく空結果で表現する
- 無効な設定値は起動前に検出する

## 未決定事項

- config の必須項目
- ペイロードをそのまま bytes で返すか、デコード層を持つか
- signal をどこまで提供するか
- 複数 endpoint の管理方法
