# Docs

このディレクトリには、`hakoniwa-godot` の設計判断と実装方針を残します。

## 役割

- `quick_start.md`: 最短で `HakoniwaSimNode` を起動する手順
- `architecture.md`: リポジトリ全体の構成方針
- `pdu_endpoint_design.md`: `hakoniwa-pdu-endpoint` 統合設計
- `packaging_strategy.md`: Godot パッケージとしての配布方針
- `installation.md`: 一般利用者向け導入手順
- `developer_build.md`: 開発者向け build / release / artifact 手順
- `api_overview.md`: API の入口と考え方
- `api_reference.md`: API 仕様
- `api_sequences.md`: API の利用順序
- `codec_plugin_design.md`: message codec plugin の設計方針
- `core_pro_design.md`: `hakoniwa-core-pro` の時間同期設計
- `core_pro_user_interface.md`: `hakoniwa-core-pro` 統合時の利用者インタフェース原型
- `core_pro_test_design.md`: `hakoniwa-core-pro` 統合のテスト設計
- `robot_sync_design.md`: `addons/hakoniwa_robot_sync` と robot profile JSON の設計方針

README には概要と導入手順を置き、設計判断や詳細仕様は `docs/` 側に寄せます。
