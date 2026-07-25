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

Windows / WSL2 から実行する場合:

```bash
bash tools/run_codec_smoke_wsl.sh --godot-bin /mnt/c/path/to/Godot.exe --quit
```

この runner は test project 配下へ `addons/` を同期してから起動する。

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

Windows ネイティブでは、使用する Hakoniwa Core 設定を明示することを推奨します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_core_pro_smoke.ps1 `
  -GodotBin C:\path\to\Godot_console.exe `
  -HakoConfigPath C:\path\to\cpp_core_config.json
```

Windows / WSL2:

```bash
bash tools/run_core_pro_smoke_wsl.sh \
  --godot-bin /mnt/c/path/to/Godot_console.exe \
  --hako-config-path /mnt/c/path/to/cpp_core_config.json
```

`-HakoConfigPath` / `--hako-config-path` は後方互換のため必須にはしていません。未指定の場合、runner は現在の `HAKO_CONFIG_PATH` を継承するか、環境変数がなければ Hakoniwa Core のデフォルト設定を使い、その選択を WARNING で表示します。smoke test がどの core 設定を参照しているかを明示的に確認してください。

Windows runner は test project の `addons` も起動前に確認します。Git for Windows で POSIX symlink が通常ファイルとして checkout されていた場合や `addons` が存在しない場合は、repo root の `addons/` を実ディレクトリとしてコピーして正規化します。正常な symbolic link はそのまま使用します。

`core_pro_smoke` では Godot の `--quit` を付けません。このテストは conductor と start / stop / reset / restart / step を複数 frame にわたって実行し、正常完了時に GDScript 自身が `HAKO_CORE_SMOKE_OK` を出力して `get_tree().quit(0)` します。

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
