#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PYTHON_BIN="${PYTHON_BIN:-/Users/tmori/.pyenv/versions/3.12.3/bin/python3}"
CONFIG_PATH="${1:-${REPO_ROOT}/examples/python_pdu_minimal/config/endpoint_shm_with_pdu_python.json}"

cd "${REPO_ROOT}"
"${PYTHON_BIN}" "${REPO_ROOT}/examples/python_pdu_minimal/python_controller.py" "${CONFIG_PATH}"
