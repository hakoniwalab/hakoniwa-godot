#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

godot_bin=""
project_dir=""
build_dir=""
config="Release"
wait_sec="1"
delta_usec="10000"
max_delay_usec="20000"
quit_after_run="false"
sync_addons="true"
keep_conductor="false"

usage() {
  cat <<'EOF'
Usage:
  bash tools/run_core_pro_smoke_wsl.sh --godot-bin /mnt/c/path/to/Godot.exe [options]

Options:
  --godot-bin PATH
  --project-dir PATH
  --build-dir PATH
  --config Debug|Release
  --wait-sec N
  --conductor-delta-usec N
  --conductor-max-delay-usec N
  --quit
  --no-sync-addons
  --keep-conductor
EOF
}

if ! command -v wslpath >/dev/null 2>&1; then
  echo "tools/run_core_pro_smoke_wsl.sh requires WSL with wslpath available." >&2
  exit 1
fi

if ! command -v powershell.exe >/dev/null 2>&1; then
  echo "tools/run_core_pro_smoke_wsl.sh requires powershell.exe in PATH." >&2
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
    --build-dir)
      build_dir="$(to_windows_path "$2")"
      shift 2
      ;;
    --config)
      config="$2"
      shift 2
      ;;
    --wait-sec)
      wait_sec="$2"
      shift 2
      ;;
    --conductor-delta-usec)
      delta_usec="$2"
      shift 2
      ;;
    --conductor-max-delay-usec)
      max_delay_usec="$2"
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
    --keep-conductor)
      keep_conductor="true"
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
  -File "$(wslpath -w "${SCRIPT_DIR}/run_core_pro_smoke.ps1")"
  -GodotBin "${godot_bin}"
  -Configuration "${config}"
  -WaitSec "${wait_sec}"
  -ConductorDeltaUsec "${delta_usec}"
  -ConductorMaxDelayUsec "${max_delay_usec}"
)

if [[ -n "${project_dir}" ]]; then
  cmd+=(-ProjectDir "${project_dir}")
fi

if [[ -n "${build_dir}" ]]; then
  cmd+=(-BuildDir "${build_dir}")
fi

if [[ "${quit_after_run}" == "true" ]]; then
  cmd+=(-QuitAfterRun)
fi

if [[ "${sync_addons}" == "true" ]]; then
  cmd+=(-SyncAddons)
fi

if [[ "${keep_conductor}" == "true" ]]; then
  cmd+=(-KeepConductor)
fi

"${cmd[@]}"
