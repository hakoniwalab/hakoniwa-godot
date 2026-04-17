# Tests

このディレクトリには、`hakoniwa-godot` の検証用プロジェクトを置きます。

## 役割

- `tests/smoke/`
  - 単機能の健全性確認
  - 壊れていないかを素早く確認する
- `tests/integration/`
  - 複数機能をまたぐ統合確認
  - 外部プロセスや起動順を含めて成立性を確認する

利用者向けの最小導線は `examples/` を参照してください。  
最短起動は [../docs/quick_start.md](../docs/quick_start.md) を参照してください。

## Smoke Tests

### 1. Codec / Endpoint Smoke

対象:

- `tests/smoke/basic_subscriber`

用途:

- codec load
- endpoint open / start / stop
- `latest` / `queue`
- typed message の最小確認

実行:

```bash
<GODOT_BIN> --headless --path tests/smoke/basic_subscriber --quit
```

成功条件:

- `HAKONIWA_CODEC_SMOKE_OK`

CTest から実行する場合:

```bash
ctest --test-dir build --output-on-failure
```

### 2. CorePro Smoke

対象:

- `tests/smoke/core_pro_smoke`

用途:

- `HakoniwaSimNode`
- lifecycle
- start / stop / reset / restart
- time sync の smoke

実行:

```bash
bash tools/run_core_pro_smoke.sh
```

成功条件:

- `HAKO_CORE_SMOKE_OK`

補足:

- conductor 前提です
- 単独の `Godot --headless --path ...` ではなく runner を使います

## Integration Tests

### CorePro Two Asset

対象:

- `tests/integration/core_pro_two_asset`

用途:

- `HakoniwaSimNode + internal SHM endpoint`
- Python controller
- typed PDU
- subscription
- 2 asset 構成の統合確認

実行:

```bash
# terminal 1
bash tools/run_core_pro_conductor.sh

# terminal 2
bash tools/run_core_pro_two_asset_controller.sh

# terminal 3
<GODOT_BIN> --headless --path tests/integration/core_pro_two_asset
```

成功条件:

- Godot 側: `HAKO_TWO_ASSET_OK`
- Python 側: controller 側ログが継続して流れる

補足:

- 起動順依存があります
- 複数 codec 前提なので、必要なら先に `bash tools/build_all_codecs.sh` を実行してください

## 関連ドキュメント

- [../docs/core_pro_test_design.md](../docs/core_pro_test_design.md)
- [../docs/physics_time_sync_test_plan.md](../docs/physics_time_sync_test_plan.md)
- [../docs/developer_build.md](../docs/developer_build.md)
