#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_GODOT_BIN="/Applications/Godot_mono.app/Contents/MacOS/Godot"
DEFAULT_EXAMPLE_DIR="${REPO_ROOT}/tests/smoke/core_pro_smoke"
DEFAULT_CONDUCTOR_WAIT_SEC="1"
DEFAULT_CONDUCTOR_DELTA_USEC="10000"
DEFAULT_CONDUCTOR_MAX_DELAY_USEC="20000"

KEEP_CONDUCTOR="false"
CONDUCTOR_PID=""

usage() {
  cat <<'EOF'
Usage:
  bash tools/run_core_pro_smoke.sh --conductor-cmd CMD [options]

Required:
  --conductor-cmd CMD   Command string that starts the conductor/background runtime

Options:
  --godot-bin PATH      Path to Godot executable
  --example-dir DIR     Godot project directory for the smoke test
  --wait-sec N          Seconds to wait after conductor startup before launching Godot
  --keep-conductor      Do not terminate conductor on exit

Examples:
  bash tools/run_core_pro_smoke.sh --conductor-cmd "python3 third_party/hakoniwa-core-pro/examples/hello_world/hello_world.py GodotAsset third_party/hakoniwa-core-pro/examples/hello_world/custom.json 100"

  bash tools/run_core_pro_smoke.sh \
    --conductor-delta-usec 10000 \
    --conductor-max-delay-usec 20000 \
    --godot-bin /Applications/Godot_mono.app/Contents/MacOS/Godot
EOF
}

main() {
  local godot_bin="${DEFAULT_GODOT_BIN}"
  local example_dir="${DEFAULT_EXAMPLE_DIR}"
  local conductor_cmd=""
  local wait_sec="${DEFAULT_CONDUCTOR_WAIT_SEC}"
  local conductor_delta_usec="${DEFAULT_CONDUCTOR_DELTA_USEC}"
  local conductor_max_delay_usec="${DEFAULT_CONDUCTOR_MAX_DELAY_USEC}"
  KEEP_CONDUCTOR="false"
  CONDUCTOR_PID=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --conductor-cmd)
        conductor_cmd="$2"
        shift 2
        ;;
      --godot-bin)
        godot_bin="$2"
        shift 2
        ;;
      --example-dir)
        example_dir="$2"
        shift 2
        ;;
      --wait-sec)
        wait_sec="$2"
        shift 2
        ;;
      --conductor-delta-usec)
        conductor_delta_usec="$2"
        shift 2
        ;;
      --conductor-max-delay-usec)
        conductor_max_delay_usec="$2"
        shift 2
        ;;
      --keep-conductor)
        KEEP_CONDUCTOR="true"
        shift 1
        ;;
      -h|--help|help)
        usage
        exit 0
        ;;
      *)
        echo "unknown option: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [[ -z "${conductor_cmd}" ]]; then
    conductor_cmd="DYLD_LIBRARY_PATH=${REPO_ROOT}/build/third_party/hakoniwa-core-pro/sources/conductor:${REPO_ROOT}/build/third_party/hakoniwa-core-pro/sources/assets/polling python3 -c 'import ctypes,time; lib=ctypes.CDLL(\"${REPO_ROOT}/build/third_party/hakoniwa-core-pro/sources/conductor/libconductor.dylib\"); lib.hako_conductor_start(${conductor_delta_usec},${conductor_max_delay_usec}); time.sleep(60)'"
  fi

  if [[ ! -x "${godot_bin}" ]]; then
    echo "godot executable not found: ${godot_bin}" >&2
    exit 1
  fi

  if [[ ! -d "${example_dir}" ]]; then
    echo "example dir not found: ${example_dir}" >&2
    exit 1
  fi

  cleanup() {
    if [[ "${KEEP_CONDUCTOR}" == "true" ]]; then
      return
    fi
    if [[ -n "${CONDUCTOR_PID}" ]] && kill -0 "${CONDUCTOR_PID}" 2>/dev/null; then
      kill "${CONDUCTOR_PID}" 2>/dev/null || true
      wait "${CONDUCTOR_PID}" 2>/dev/null || true
    fi
  }

  trap cleanup EXIT INT TERM

  echo "[core-pro-smoke] starting conductor: ${conductor_cmd}"
  /bin/zsh -lc "${conductor_cmd}" &
  CONDUCTOR_PID=$!

  sleep "${wait_sec}"

  echo "[core-pro-smoke] running Godot example: ${example_dir}"
  "${godot_bin}" --headless --path "${example_dir}"
}

main "$@"
