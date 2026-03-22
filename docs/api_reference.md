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

### `HakoniwaCodecRegistry`

- `plugin_paths: PackedStringArray`
- `auto_load_on_ready: bool`
- `get_last_error() -> String`
- `load_plugin(plugin_path: String) -> bool`
- `load_configured_plugins() -> int`
- `has_codec(package_name: String, message_name: String) -> bool`
- `decode(package_name: String, message_name: String, payload: PackedByteArray) -> Dictionary`
- `encode(package_name: String, message_name: String, value: Dictionary) -> PackedByteArray`

### `HakoniwaEndpointNode`

- `config_path: String`
- `codec_plugins: PackedStringArray`
- `endpoint_name: String`
- `direction: int`
- `auto_open_on_ready: bool`
- `auto_start_on_ready: bool`
- `auto_process_recv_events: bool`
- `auto_close_on_exit: bool`
- `get_backend_name() -> String`
- `probe_native_backend() -> bool`
- `open_endpoint(path: String = "") -> int`
- `close_endpoint() -> void`
- `start_endpoint() -> int`
- `post_start_endpoint() -> int`
- `stop_endpoint() -> void`
- `process_recv_events() -> void`
- `is_running() -> bool`
- `set_recv_event(robot: String, channel_id: int) -> int`
- `get_pending_count() -> int`
- `recv_raw(robot: String, pdu_name: String) -> Dictionary`
- `recv_next_raw() -> Dictionary`
- `send_raw(robot: String, pdu_name: String, payload: PackedByteArray) -> int`
- `load_codec_plugin(plugin_path: String) -> bool`
- `load_configured_codecs() -> int`
- `has_codec(package_name: String, message_name: String) -> bool`
- `encode_message(package_name: String, message_name: String, value: Dictionary) -> PackedByteArray`
- `encode_typed_message(package_name: String, message_name: String, typed_value: Variant) -> PackedByteArray`
- `decode_payload(package_name: String, message_name: String, payload: PackedByteArray) -> Dictionary`
- `decode_record(package_name: String, message_name: String, record: Dictionary) -> Dictionary`
- `to_typed_value(package_name: String, message_name: String, value: Dictionary) -> Variant`
- `decode_typed_record(package_name: String, message_name: String, record: Dictionary) -> Dictionary`
- `send_message(robot: String, pdu_name: String, package_name: String, message_name: String, value: Dictionary) -> int`
- `recv_message(robot: String, pdu_name: String, package_name: String, message_name: String) -> Dictionary`
- `recv_next_message(package_name: String, message_name: String) -> Dictionary`
- `send_typed_message(robot: String, pdu_name: String, package_name: String, message_name: String, typed_value: Variant) -> int`
- `recv_typed_message(robot: String, pdu_name: String, package_name: String, message_name: String) -> Dictionary`
- `recv_next_typed_message(package_name: String, message_name: String) -> Dictionary`
- `get_typed_endpoint(robot: String, pdu_name: String) -> Variant`
- `get_last_error_text() -> String`
- `get_last_error_code() -> int`

### `HakoniwaTypedEndpoint`

- `get_robot() -> String`
- `get_pdu_name() -> String`
- `get_package_name() -> String`
- `get_message_name() -> String`
- `send(typed_value: Variant) -> int`
- `recv() -> Variant`
- `recv_record() -> Dictionary`
- `send_dict(value: Dictionary) -> int`
- `recv_dict() -> Dictionary`

## API 要約

### `HakoniwaPduEndpoint`

- 責務: endpoint lifecycle と raw binary send / recv
- 入出力: `PackedByteArray` を含む record `Dictionary`
- codec plugin が無くても単体で利用可能

### `HakoniwaCodecRegistry`

- 責務: codec plugin のロードと message 単位の decode / encode
- `plugin_paths` は `_ready()` 自動ロード対象
- `load_plugin()` は `res://` / `user://` を実パスへ解決する
- 拡張子が省略された場合は platform ごとの shared library suffix を補完する

### `HakoniwaEndpointNode`

- 責務: `HakoniwaPduEndpoint` と `HakoniwaCodecRegistry` を束ねる GDScript wrapper
- raw API と decode 付き API の両方を提供する
- `decode_record()` / `recv_message()` / `recv_next_message()` は `{robot, channel_id, pdu_name, timestamp_ns, value}` を返す
- `decode_typed_record()` / `recv_typed_message()` / `recv_next_typed_message()` は `typed_value` を追加で返す
- typed script は `message_script_roots` 配下の `<package>/<message>.gd` から解決する
- `get_typed_endpoint()` は `config_path` から `pdu_def` を読んで `robot + pdu_name` の型を解決する

### `HakoniwaTypedEndpoint`

- 責務: 1つの `robot + pdu_name` に束縛された上位 API
- `send()` は typed object を送り、`recv()` は typed object を返す
- 型名は `HakoniwaEndpointNode.get_typed_endpoint()` が `pdu_def` から自動解決する

## 起動順序

推奨順:

1. `HakoniwaCodecRegistry` で codec plugin をロードする
2. `HakoniwaPduEndpoint` を `open()` する
3. `HakoniwaPduEndpoint` を `start()` する

## fallback

- codec plugin が見つからない場合、`HakoniwaCodecRegistry.decode()` は空 `Dictionary` を返す
- codec plugin が見つからない場合、`HakoniwaCodecRegistry.encode()` は空 `PackedByteArray` を返す
- その場合でも `HakoniwaPduEndpoint` の raw API は利用できる
