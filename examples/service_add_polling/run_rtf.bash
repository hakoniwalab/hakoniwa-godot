#!/bin/bash
# RTF of Godot as a 1 ms polling asset (no rendering): only the conductor and Godot,
# or with CLIENT=1 also a Service/Add client asset.
# Usage: CORE_PRO_BUILD=<core-pro>/cmake-build [DURATION_SEC=10] [CLIENT=1] bash examples/service_add_polling/run_rtf.bash
set -u

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
EXAMPLE_DIR=${REPO_ROOT}/examples/service_add_polling
CORE_PRO_BUILD=${CORE_PRO_BUILD:?set CORE_PRO_BUILD to a hakoniwa-core-pro build directory}
GODOT_BIN=${GODOT_BIN:-/Applications/Godot_mono.app/Contents/MacOS/Godot}
DURATION_SEC=${DURATION_SEC:-10}
BIN=${CORE_PRO_BUILD}/examples/service_polling
HAKO_CMD=${CORE_PRO_BUILD}/sources/command/hako-cmd
SERVICE_JSON=${EXAMPLE_DIR}/config/service.json
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hako-godot-rtf.XXXXXX")

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

wait_for() {
    local log=$1 pattern=$2 timeout=$3 elapsed=0
    while [ "${elapsed}" -lt "$((timeout * 10))" ]; do
        grep -q "${pattern}" "${log}" 2>/dev/null && return 0
        sleep 0.1
        elapsed=$((elapsed + 1))
    done
    return 1
}

"${BIN}/polling_conductor" > "${WORK_DIR}/conductor.log" 2>&1 & PIDS+=($!)
sleep 1
"${GODOT_BIN}" --headless --fixed-fps 1000 --path "${EXAMPLE_DIR}" > "${WORK_DIR}/godot.log" 2>&1 & PIDS+=($!)
wait_for "${WORK_DIR}/godot.log" "SERVER registered" 30 || { echo "FAIL: Godot did not register"; exit 1; }
if [ "${CLIENT:-0}" = "1" ]; then
    "${BIN}/polling_client" "${SERVICE_JSON}" 1000000 ${CLIENT_OPTION:-} > "${WORK_DIR}/client.log" 2>&1 & PIDS+=($!)
    wait_for "${WORK_DIR}/client.log" "CLIENT registered" 10 || { echo "FAIL: client did not register"; exit 1; }
fi

"${HAKO_CMD}" start > /dev/null 2>&1
sleep "${DURATION_SEC}"
"${HAKO_CMD}" stop > /dev/null 2>&1
sleep 1

# RTF from the first and last samples (one per simulated second).
grep "^RTF_SAMPLE" "${WORK_DIR}/godot.log" | awk -F'[= ]' '
    NR == 1 { s0 = $3; w0 = $5 }
    { s1 = $3; w1 = $5; n = NR }
    END {
        if (n < 2) { print "FAIL: not enough samples"; exit 1 }
        printf "samples=%d sim_sec=%.1f wall_sec=%.2f RTF=%.2f\n", n, (s1 - s0) / 1e6, (w1 - w0) / 1e6, (s1 - s0) / (w1 - w0)
    }'
[ -f "${WORK_DIR}/client.log" ] && echo "client responses: $(grep -c 'CLIENT response' "${WORK_DIR}/client.log")"
echo "logs: ${WORK_DIR}"
