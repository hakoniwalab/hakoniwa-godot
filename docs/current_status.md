# Current Status

現在のマイルストーン: **`HakoniwaSimNode + internal SHM endpoint + Python controller` による 2 asset 時刻同期・typed PDU 通信まで**

## 達成済み

- Godot プラグインの最小土台を作成
- GDExtension のビルドに成功
- `hakoniwa-pdu-endpoint` へのリンク確認
- `open / start / stop / is_running` の最小 API を実装
- `send_by_name / recv_by_name` による `latest` 動作確認
- `recv_next()` による `queue` 動作確認
- `set_recv_event / get_pending_count` による pending 管理確認
- `HakoniwaCodecRegistry` による codec plugin load に成功
- `hako_msgs` codec plugin の `encode / decode` smoke test に成功
- message package ごとの shared library plugin 生成基盤を追加
- `HakoniwaEndpointNode` による GDScript wrapper を追加
- `HakoniwaTypedEndpoint` による `robot + pdu_name` 束縛 API を追加
- `addons/hakoniwa_msgs` 生成導線を追加
- typed endpoint で単純型、複雑型、可変長配列の動作確認
- `HakoniwaSimNode` による `hakoniwa-core-pro` polling asset 統合
- start / stop / reset / restart lifecycle smoke に成功
- `simtime == world_time` の `tests/smoke/core_pro_smoke` に成功
- `HakoniwaSimNode + internal SHM endpoint + Python controller` の 2 asset smoke に成功
- `geometry_msgs/Twist` の `motor` / `pos` で typed PDU 相互通信に成功
- `HakoniwaEndpointNode` に low-level pull API と ROS 風 subscription API を実装
- internal SHM endpoint では `tick()` 経由で `dispatch_recv_events()` が動作
- codec `.gdextension` 初期化順を framework 側で吸収
- addon artifact の staging / archive 導線を整備
  - macOS / Linux: `tools/addon_artifact_tool.sh`
  - Windows: `tools/addon_artifact_tool.ps1`

## まだ対象外

- `hakoniwa-pdu-rpc` の操作系統合
- codec plugin / message addon の自動 discovery
- Windows 実機での build / load 回帰確認

## 配布モデル

```text
addons/
├─ hakoniwa/
│  ├─ bin/          # platform 依存: native binary
│  ├─ codecs/       # platform 依存: codec plugin
│  └─ scripts/      # platform 非依存: GDScript wrapper
└─ hakoniwa_msgs/   # platform 非依存: generated GDScript message classes
```

`addons/hakoniwa` は `OS + architecture` ごとに配布物が分かれます。  
`addons/hakoniwa_msgs` は platform 非依存の message 定義層として独立して扱います。

このリポジトリでは `addons/` 自体を正本にはせず、source から生成・配布する成果物として扱います。

現状の release 状態:

- `macOS arm64` は build / artifact 手順とも確認済み
- `Linux` は artifact tool が対応している
- `Windows x86_64` は artifact tool が対応している
- ただし回帰確認の基準 platform は引き続き `macOS arm64`

## Common Codecs

`builtin_interfaces`, `can_msgs`, `drone_srv_msgs`, `ev3_msgs`, `geometry_msgs`, `hako_mavlink2_msgs`, `hako_mavlink_msgs`, `hako_msgs`, `hako_srv_msgs`, `mavros_msgs`, `nav_msgs`, `sensor_msgs`, `std_msgs`, `tf2_msgs`
