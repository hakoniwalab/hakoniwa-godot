# API Reference

## 目的

公開 API の仕様を、実装と対応づけて参照できるようにする。

## この文書に含める内容

- クラス名
- メソッド名
- 引数
- 戻り値
- 前提条件
- エラー条件
- モード別の挙動

## 初期対象

### `HakoniwaPduEndpoint`

想定している記載対象:

- `open(config_path: String) -> int`
- `close() -> void`
- `start() -> int`
- `post_start() -> int`
- `stop() -> void`
- `process_recv_events() -> void`
- `recv_by_name(robot: String, pdu_name: String) -> Dictionary`
- `recv_next() -> Dictionary`
- `set_recv_event(robot: String, channel_id: int) -> int`
- `get_pending_count() -> int`
- `send_by_name(robot: String, pdu_name: String, payload: PackedByteArray) -> int`
- `is_running() -> bool`

実装開始後は、この文書を API の正本として更新する。
