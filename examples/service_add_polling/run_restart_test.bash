#!/bin/bash
# Godot as the Service/Add server (registered polling asset, 1 ms physics tick).
# The conductor, the client and hako-cmd come from a hakoniwa-core-pro build of the
# same revision as third_party/hakoniwa-core-pro.
# Checks: requests are answered, and again after stop -> reset -> start in the same processes.
# Usage: CORE_PRO_BUILD=<core-pro>/cmake-build bash examples/service_add_polling/run_restart_test.bash
set -u

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
EXAMPLE_DIR=${REPO_ROOT}/examples/service_add_polling
CORE_PRO_BUILD=${CORE_PRO_BUILD:?set CORE_PRO_BUILD to a hakoniwa-core-pro build directory}
GODOT_BIN=${GODOT_BIN:-/Applications/Godot_mono.app/Contents/MacOS/Godot}
BIN=${CORE_PRO_BUILD}/examples/service_polling
HAKO_CMD=${CORE_PRO_BUILD}/sources/command/hako-cmd
SERVICE_JSON=${EXAMPLE_DIR}/config/service.json
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hako-godot-add.XXXXXX")

# Godot resolves the extension classes from this list (written by the editor import;
# written here so that no import run is needed).
mkdir -p "${EXAMPLE_DIR}/.godot"
printf '%s\n' res://addons/hakoniwa/hakoniwa.gdextension res://addons/hakoniwa/codecs/hako_srv_msgs_codec.gdextension \
    > "${EXAMPLE_DIR}/.godot/extension_list.cfg"

mkdir -p "${WORK_DIR}/mmap"
cat > "${WORK_DIR}/cpp_core_config.json" <<JSON
{
  "shm_type": "mmap",
  "core_mmap_path": "${WORK_DIR}/mmap",
  "asset_timeout_usec": 600000000
}
JSON
export HAKO_CONFIG_PATH="${WORK_DIR}/cpp_core_config.json"
export DYLD_LIBRARY_PATH=${CORE_PRO_BUILD}/sources/assets/polling:${CORE_PRO_BUILD}/sources/assets/callback:${CORE_PRO_BUILD}/sources/conductor
export LD_LIBRARY_PATH=${DYLD_LIBRARY_PATH}

PIDS=()
cleanup() {
    for pid in "${PIDS[@]:-}"; do
        [ -n "${pid}" ] && kill "${pid}" 2>/dev/null
    done
    wait 2>/dev/null
}
trap cleanup EXIT

# wait_for LOG PATTERN COUNT TIMEOUT_SEC
wait_for() {
    local log=$1 pattern=$2 count=$3 timeout=$4 elapsed=0
    while [ "${elapsed}" -lt "$((timeout * 10))" ]; do
        [ "$(grep -c "${pattern}" "${log}" 2>/dev/null)" -ge "${count}" ] && return 0
        sleep 0.1
        elapsed=$((elapsed + 1))
    done
    return 1
}

fail() {
    echo "FAIL: $1 (logs: ${WORK_DIR})"
    exit 1
}

"${BIN}/polling_conductor" > "${WORK_DIR}/conductor.log" 2>&1 & PIDS+=($!)
sleep 1
"${GODOT_BIN}" --headless --fixed-fps 1000 --path "${EXAMPLE_DIR}" > "${WORK_DIR}/godot.log" 2>&1 & PIDS+=($!)
wait_for "${WORK_DIR}/godot.log" "SERVER registered" 1 30 || fail "Godot server did not register"
"${BIN}/polling_client" "${SERVICE_JSON}" 3 ${CLIENT_OPTION:-} > "${WORK_DIR}/client.log" 2>&1 & PIDS+=($!)
wait_for "${WORK_DIR}/client.log" "CLIENT registered" 1 10 || fail "client did not register"

"${HAKO_CMD}" start > /dev/null 2>&1
wait_for "${WORK_DIR}/client.log" "^RESULT" 1 20 || fail "no result in the first run"
"${HAKO_CMD}" stop > /dev/null 2>&1
sleep 2
"${HAKO_CMD}" reset > /dev/null 2>&1
sleep 2
"${HAKO_CMD}" start > /dev/null 2>&1
wait_for "${WORK_DIR}/client.log" "^RESULT" 2 20 || fail "no result after restart"
grep -q "ERROR" "${WORK_DIR}/client.log" && fail "client reported an error"

grep "^RESULT" "${WORK_DIR}/client.log"
grep -c "SERVER request" "${WORK_DIR}/godot.log" | sed 's/^/server requests: /'
echo "PASS (logs: ${WORK_DIR})"
