#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DELTA_USEC="${1:-10000}"
MAX_DELAY_USEC="${2:-20000}"
SLEEP_SEC="${3:-60}"
PYTHON_BIN="${PYTHON_BIN:-/Users/tmori/.pyenv/versions/3.12.3/bin/python3}"

DYLD_LIBRARY_PATH="${REPO_ROOT}/build/third_party/hakoniwa-core-pro/sources/conductor:${REPO_ROOT}/build/third_party/hakoniwa-core-pro/sources/assets/polling" \
"${PYTHON_BIN}" -c "import ctypes,time; lib=ctypes.CDLL('${REPO_ROOT}/build/third_party/hakoniwa-core-pro/sources/conductor/libconductor.dylib'); lib.hako_conductor_start(${DELTA_USEC},${MAX_DELAY_USEC}); time.sleep(${SLEEP_SEC})"
