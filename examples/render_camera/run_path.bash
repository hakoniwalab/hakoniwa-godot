#!/bin/bash
# Camera on a path: Godot RenderCamera (registered polling asset, 1 ms tick) and the
# core-pro camera_path_client, which asks for one image every PERIOD_USEC of
# simulation time with the next pose of PATH_CSV (see make_road_path.py).
# Reports the round trip per frame and the RTF of the whole run.
# Usage: CORE_PRO_BUILD=<core-pro>/cmake-build PATH_CSV=<path.csv> [WORLD_GLB=<city.glb>]
#        [SIZE=1280x720] [PERIOD_USEC=33000] [DUMP_DIR=<dir>] bash examples/render_camera/run_path.bash
set -u

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
EXAMPLE_DIR=${REPO_ROOT}/examples/render_camera
CORE_PRO_BUILD=${CORE_PRO_BUILD:?set CORE_PRO_BUILD to a hakoniwa-core-pro build directory}
GODOT_BIN=${GODOT_BIN:-/Applications/Godot_mono.app/Contents/MacOS/Godot}
PATH_CSV=${PATH_CSV:?set PATH_CSV to a camera path (make_road_path.py)}
SIZE=${SIZE:-1280x720}
PERIOD_USEC=${PERIOD_USEC:-33000}
BIN=${CORE_PRO_BUILD}/examples/service_polling
HAKO_CMD=${CORE_PRO_BUILD}/sources/command/hako-cmd
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hako-godot-path.XXXXXX")

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
    PIDS=()
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

width=${SIZE%x*}
height=${SIZE#*x}
bytes=$((width * height * 3))
cat > "${WORK_DIR}/service.json" <<JSON
{
    "pduMetaDataSize": 24,
    "services": [
        {
            "name": "HakoCamera/RenderCamera",
            "type": "hako_srv_msgs/RenderCamera",
            "maxClients": 1,
            "pduSize": {
                "server": { "heapSize": 256, "baseSize": 464 },
                "client": { "heapSize": $((bytes + 1024)), "baseSize": 576 }
            }
        }
    ],
    "nodes": []
}
JSON
GODOT_ARGS=()
[ -n "${WORLD_GLB:-}" ] && GODOT_ARGS+=("--world-glb=${WORLD_GLB}")
CLIENT_ARGS=()
[ -n "${DUMP_DIR:-}" ] && mkdir -p "${DUMP_DIR}" && CLIENT_ARGS+=("--dump-dir=${DUMP_DIR}")

"${BIN}/polling_conductor" > "${WORK_DIR}/conductor.log" 2>&1 & PIDS+=($!)
sleep 1
"${GODOT_BIN}" --fixed-fps 1000 --resolution 320x240 --path "${EXAMPLE_DIR}" -- \
    "--service-json=${WORK_DIR}/service.json" ${GODOT_ARGS[@]+"${GODOT_ARGS[@]}"} > "${WORK_DIR}/godot.log" 2>&1 & PIDS+=($!)
wait_for "${WORK_DIR}/godot.log" "SERVER registered" 60 || { echo "FAIL: Godot did not register (${WORK_DIR})"; exit 1; }
"${BIN}/camera_path_client" "${WORK_DIR}/service.json" "${SIZE}" "${PATH_CSV}" "${PERIOD_USEC}" \
    "${WORK_DIR}/client.csv" ${CLIENT_ARGS[@]+"${CLIENT_ARGS[@]}"} > "${WORK_DIR}/client.log" 2>&1 & CLIENT=$!
PIDS+=(${CLIENT})
sleep 1
"${HAKO_CMD}" start > /dev/null 2>&1
wait "${CLIENT}"
"${HAKO_CMD}" stop > /dev/null 2>&1
grep -E "^CLIENT done|^ERROR" "${WORK_DIR}/client.log"
python3 - "${WORK_DIR}/client.csv" <<'PY'
import csv, statistics, sys
rows = list(csv.DictReader(open(sys.argv[1])))
rtt = sorted((int(r["response_in_ns"]) - int(r["send_ns"])) / 1e6 for r in rows)
print(f"frames={len(rows)} rtt_mean_ms={statistics.mean(rtt):.2f} rtt_p99_ms={rtt[int(len(rtt) * 0.99) - 1]:.2f} rtt_max_ms={rtt[-1]:.2f}")
PY
echo "logs: ${WORK_DIR}"
