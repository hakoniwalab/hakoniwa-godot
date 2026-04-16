#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${1:-${REPO_ROOT}/build}"

cd "${REPO_ROOT}"

echo "[build-all-codecs] configure"
bash tools/codec_plugin_tool.sh configure --build-dir "${BUILD_DIR}" --packages all

echo "[build-all-codecs] build"
bash tools/codec_plugin_tool.sh build --build-dir "${BUILD_DIR}"

echo "[build-all-codecs] sync message addons"
bash tools/message_addon_tool.sh sync --packages all

echo "[build-all-codecs] done"
