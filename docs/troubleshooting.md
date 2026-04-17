# Troubleshooting

## 目的

`hakoniwa-godot` 利用時によく踏む初期化・設定ミスを残す。

現時点では、特に codec plugin と GDExtension 初期化順の問題を重点対象とする。

## codec plugin 利用時の原則

`hakoniwa-godot` の codec plugin は、単なる shared library ではない。

- `<package>_codec.<shared-library>`
- `<package>_codec.gdextension`

の組で成り立つ。

特に `geometry_msgs_codec` のような plugin は、内部で `godot::Dictionary` や `godot::PackedByteArray` を生成する。
そのため、単に `.dylib` / `.so` / `.dll` を `dlopen()` するだけでは不十分で、対応する `.gdextension` の初期化文脈が必要になる。

## 標準 API を使う場合

以下の API を使う限り、codec plugin の `.gdextension` 初期化は framework 側が吸収する。

- `HakoniwaSimNode`
- `HakoniwaEndpointNode`

つまり、通常利用者は codec plugin path だけ指定すればよい。

例:

```gdscript
endpoint.codec_plugins = PackedStringArray([
    "res://addons/hakoniwa/codecs/geometry_msgs_codec"
])
endpoint.load_configured_codecs()
```

このとき plugin path は、拡張子なしの package 名ベースを推奨する。

## 低レベル API を直接使う場合

以下を直接使う場合は注意が要る。

- `HakoniwaCodecRegistry`
- native 側の codec loader
- 独自の `dlopen()`

この場合、単に shared library を開くだけでは不十分で、先に対応する `.gdextension` resource を Godot にロードさせる必要がある。

例:

```gdscript
var extension := load("res://addons/hakoniwa/codecs/geometry_msgs_codec.gdextension")
if extension == null:
    push_error("geometry_msgs_codec.gdextension could not be loaded")
    return

var codecs := HakoniwaCodecRegistry.new()
add_child(codecs)
codecs.load_plugin("res://addons/hakoniwa/codecs/geometry_msgs_codec")
```

この前提を満たさないと、`load_plugin()` 自体は成功しても、実際の `encode()` / `decode()` で落ちることがある。

## custom codec 作成時の手順

1. `hakoniwa-pdu-registry` 側で対象 package の Godot codec 生成対象を用意する
2. `tools/codec_plugin_tool.sh configure --packages "<package>"` を実行する
3. `tools/codec_plugin_tool.sh build` で plugin を build する
4. 出力物が両方あることを確認する

確認対象:

- `addons/hakoniwa/codecs/<package>_codec.<shared-library>`
- `addons/hakoniwa/codecs/<package>_codec.gdextension`

5. 必要なら `addons/hakoniwa_msgs/<package>/*.gd` を `tools/message_addon_tool.sh sync --packages "<package>"` で同期する
6. まず `tests/smoke/basic_subscriber` 相当の endpoint-only smoke test で encode / decode を確認する
7. その後 `HakoniwaSimNode` や `hakoniwa-core-pro` 統合へ進む

重要なのは、いきなり `core-pro` 統合へ持ち込まず、

- endpoint-only
- typed send / recv
- internal endpoint
- core-pro

の順で段階確認すること。

## 今回の事例

症状:

- `basic_subscriber` では `geometry_msgs/Twist` が通る
- `core_pro_two_asset` では `send_dict()` / `recv_dict()` で crash する

実際の crash 点:

- `godot_to_pdu_Twist()`
- `pdu_to_godot_Twist()`
- `godot::PackedByteArray::PackedByteArray()`
- `godot::Dictionary::Dictionary()`

切り分け:

1. endpoint-only の `geometry_msgs/Twist` smoke を追加
2. そこでは成功
3. `core-pro + internal SHM endpoint` 経路だけ失敗
4. 差分を調べると、`basic_subscriber` は `geometry_msgs_codec.gdextension` を先に `load()` していた
5. 一方、内部 endpoint は `.dylib` を直接 plugin loader に渡していた

原因:

- codec 実装そのものではなく、GDExtension 初期化順の不足

対応:

- `HakoniwaEndpointNode.load_codec_plugin()` が、plugin path から対応する `.gdextension` を自動で `load()` するように修正
- `HakoniwaSimNode` の internal endpoint でも codec path を `res://.../geometry_msgs_codec` に統一

結果:

- `core_pro_two_asset` で `motor` / `pos` の typed send / recv が成功
- `simtime == world_time` の 5 step smoke が通過

## subscription を作ったのに callback が来ない

症状:

- `create_subscription_*()` は成功する
- callback / signal が一度も発火しない
- transport 側ログに `No subscribers found ...` が出る

まず確認すること:

1. 対象 endpoint JSON の entry で `notify_on_recv: true` になっているか
2. `_process()` / `_physics_process()` / `HakoniwaSimNode.tick()` から `dispatch_recv_events()` が呼ばれているか

補足:

- low-level pull API だけを使う場合は、`notify_on_recv` と high-level subscription は不要
- high-level subscription API は native callback を内部 queue に積み、`dispatch_recv_events()` で Godot main thread 上へ配送する
- `HakoniwaSimNode` の internal SHM endpoint では `tick()` が `dispatch_recv_events()` を呼ぶ
- 独立 `HakoniwaEndpointNode` では、利用者が `dispatch_recv_events()` を呼ぶ必要がある

## 疑うべきログ

以下のような stack が見えたら、この問題を疑う。

- `godot::Dictionary::Dictionary()`
- `godot::PackedByteArray::PackedByteArray()`
- `geometry_msgs_codec.dylib`
- `pdu_to_godot_*`
- `godot_to_pdu_*`

特に、

- `load_plugin()` は成功する
- 実際の `encode()` / `decode()` で crash する

という形なら、codec の未ロードではなく `.gdextension` 初期化順の可能性が高い。
