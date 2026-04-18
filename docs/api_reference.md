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

### `HakoniwaCoreAsset`

- `initialize_asset(asset_name: String) -> int`
- `unregister_asset() -> int`
- `poll_event() -> int`
- `get_simulation_state() -> int`
- `get_world_time_usec() -> int`
- `get_simtime_usec() -> int`
- `notify_simtime(simtime_usec: int) -> void`
- `start_feedback_ok() -> int`
- `stop_feedback_ok() -> int`
- `reset_feedback_ok() -> int`
- `get_last_error() -> String`

### `HakoniwaSimNode`

- signal:
  - `initialized`
    - `initialize()` 成功後に deferred emit される
    - `auto_initialize_on_ready=true` の場合に、同一 scene の他 node から `get_endpoint()` / subscription 作成を始める起点として使う
- `asset_name: String`
- `use_internal_shm_endpoint: bool`
- `shm_endpoint_config_path: String`
- `auto_initialize_on_ready: bool`
- `auto_unregister_on_exit: bool`
- `auto_tick_on_physics_process: bool`
- `initialize() -> int`
- `shutdown() -> void`
- `set_callbacks(callbacks: HakoniwaSimulationCallbacks) -> void`
- `request_start() -> int`
- `request_stop() -> int`
- `request_reset() -> int`
- `tick() -> bool`
- `get_state() -> int`
- `get_world_time_usec() -> int`
- `get_simtime_usec() -> int`
- `get_typed_endpoint(robot: String, pdu_name: String) -> Variant`
- `get_endpoint() -> Variant`
- `get_last_error_text() -> String`

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
- `dispatch_recv_events() -> int`
- `is_running() -> bool`
- `set_recv_event(robot: String, channel_id: int) -> int`
- `get_pending_count() -> int`
- `create_subscription_raw(robot: String, pdu_name: String, callback: Callable = Callable()) -> int`
- `create_subscription_message(robot: String, pdu_name: String, package_name: String, message_name: String, callback: Callable = Callable()) -> int`
- `create_subscription_typed(robot: String, pdu_name: String, callback: Callable = Callable()) -> int`
- `destroy_subscription(subscription_id: int) -> bool`
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

### `HakoniwaCoreAsset`

- 責務: `hakoniwa-core-pro` polling API の native wrapper
- PDU I/O は持たず、時間同期と asset lifecycle だけを担当する
- Godot 側の上位 wrapper から 1 instance 前提で使う
- `get_world_time_usec()` は箱庭全体の時刻を返す
- `get_simtime_usec()` は当該 asset が最後に進めた時刻を返す

### `HakoniwaSimNode`

- 責務: `HakoniwaCoreAsset` を Godot lifecycle に接続する GDScript wrapper
- `Start` / `Stop` / `Reset` event を callback 実行へ変換する
- `request_start()` / `request_stop()` / `request_reset()` で lifecycle event を要求できる
- `tick() -> bool` により simulation step 実行可否を返す
- 内部 SHM endpoint の start / stop / pump を統合できる
- 同一アプリ内で複数 instance を許可しない
- `get_state()` は debug / UI 表示用であり、制御用ではない
- `get_simtime_usec()` は asset 側の現在 simtime を返す
- `get_typed_endpoint()` は internal SHM endpoint 利用時の sugar API
- WebSocket など他 transport の endpoint は `HakoniwaSimNode` の管理対象外

### `HakoniwaPduEndpoint`

- 責務: endpoint lifecycle と raw binary send / recv
- 入出力: `PackedByteArray` を含む record `Dictionary`
- codec plugin が無くても単体で利用可能

### `HakoniwaCodecRegistry`

- 責務: codec plugin のロードと message 単位の decode / encode
- `plugin_paths` は `_ready()` 自動ロード対象
- `load_plugin()` は `res://` / `user://` を実パスへ解決する
- 拡張子が省略された場合は platform ごとの shared library suffix を補完する
- low-level API として扱う。通常利用では `HakoniwaEndpointNode` 経由を推奨する
- `.gdextension` resource の初期化は自動では吸収しないため、直接利用時は呼び出し側が初期化順を保証する必要がある

### `HakoniwaEndpointNode`

- 責務: `HakoniwaPduEndpoint` と `HakoniwaCodecRegistry` を束ねる GDScript wrapper
- raw API と decode 付き API の両方を提供する
- codec plugin path に対応する `.gdextension` resource のロードを内部で吸収する
- `decode_record()` / `recv_message()` / `recv_next_message()` は `{robot, channel_id, pdu_name, timestamp_ns, value}` を返す
- `decode_typed_record()` / `recv_typed_message()` / `recv_next_typed_message()` は `typed_value` を追加で返す
- typed script は `message_script_roots` 配下の `<package>/<message>.gd` から解決する
- `get_typed_endpoint()` は `config_path` から `pdu_def` を読んで `robot + pdu_name` の型を解決する
- 受信 API は 2 層に分かれる
  - low-level pull API:
    - `process_recv_events()`
    - `set_recv_event()`
    - `get_pending_count()`
    - `recv_next_*()`
  - high-level subscription API:
    - `create_subscription_*()`
    - `destroy_subscription()`
    - `dispatch_recv_events()`
- high-level subscription API は native receive callback を内部 queue に積み、`dispatch_recv_events()` で Godot main thread 上へ配送する
- signal:
  - `raw_message_received(subscription_id, record)`
  - `message_received(subscription_id, message, record)`
  - `typed_message_received(subscription_id, typed_value, record)`
- high-level subscription API を使う場合、endpoint JSON の対象 entry で `notify_on_recv: true` が必要

### `HakoniwaTypedEndpoint`

- 責務: 1つの `robot + pdu_name` に束縛された上位 API
- `send()` は typed object を送り、`recv()` は typed object を返す
- 型名は `HakoniwaEndpointNode.get_typed_endpoint()` が `pdu_def` から自動解決する

## 起動順序

推奨順:

1. `HakoniwaCodecRegistry` で codec plugin をロードする
2. `HakoniwaPduEndpoint` を `open()` する
3. `HakoniwaSimNode` を `initialize()` する
4. `Start` event 後に `HakoniwaPduEndpoint` を `start()` / `post_start()` する

codec plugin path の推奨形:

- `res://addons/hakoniwa/codecs/hako_msgs_codec`
- `res://addons/hakoniwa/codecs/std_msgs_codec`
- `res://addons/hakoniwa/codecs/geometry_msgs_codec`

通常利用では、`.dylib` / `.so` / `.dll` を直接指定しない。

## fallback

- codec plugin が見つからない場合、`HakoniwaCodecRegistry.decode()` は空 `Dictionary` を返す
- codec plugin が見つからない場合、`HakoniwaCodecRegistry.encode()` は空 `PackedByteArray` を返す
- その場合でも `HakoniwaPduEndpoint` の raw API は利用できる

## 注意

- `HakoniwaSimNode` / `HakoniwaEndpointNode` を使う場合は、codec plugin の GDExtension 初期化順は framework 側が吸収する
- `HakoniwaCodecRegistry` を直接使う場合は、対応する `<package>_codec.gdextension` のロードを先に済ませること
- `HakoniwaSimNode` の internal SHM endpoint は `tick()` の中で `dispatch_recv_events()` を呼ぶ
- WebSocket / TCP / Zenoh / MQTT など独立 `HakoniwaEndpointNode` では、利用者が main loop から `dispatch_recv_events()` または low-level pull API を呼ぶ
