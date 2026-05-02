#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

godot_bin=""
project_dir=""
quit_after_run="false"
sync_addons="true"

usage() {
  cat <<'EOF'
Usage:
  bash tools/run_codec_smoke_wsl.sh --godot-bin /mnt/c/path/to/Godot.exe [options]

Options:
  --godot-bin PATH
  --project-dir PATH
  --quit
  --no-sync-addons
EOF
}

if ! command -v wslpath >/dev/null 2>&1; then
  echo "tools/run_codec_smoke_wsl.sh requires WSL with wslpath available." >&2
  exit 1
fi

if ! command -v powershell.exe >/dev/null 2>&1; then
  echo "tools/run_codec_smoke_wsl.sh requires powershell.exe in PATH." >&2
  exit 1
fi

to_windows_path() {
  local path="$1"
  wslpath -w "${path}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --godot-bin)
      godot_bin="$(to_windows_path "$2")"
      shift 2
      ;;
    --project-dir)
      project_dir="$(to_windows_path "$2")"
      shift 2
      ;;
    --quit)
      quit_after_run="true"
      shift
      ;;
    --no-sync-addons)
      sync_addons="false"
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${godot_bin}" ]]; then
  echo "--godot-bin is required" >&2
  usage >&2
  exit 1
fi

cmd=(
  powershell.exe
  -NoProfile
  -ExecutionPolicy Bypass
  -File "$(wslpath -w "${SCRIPT_DIR}/run_codec_smoke.ps1")"
  -GodotBin "${godot_bin}"
)

if [[ -n "${project_dir}" ]]; then
  cmd+=(-ProjectDir "${project_dir}")
fi

if [[ "${quit_after_run}" == "true" ]]; then
  cmd+=(-QuitAfterRun)
fi

if [[ "${sync_addons}" == "true" ]]; then
  cmd+=(-SyncAddons)
fi

"${cmd[@]}"
