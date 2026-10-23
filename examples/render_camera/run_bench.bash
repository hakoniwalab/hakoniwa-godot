#!/bin/bash
# RenderCamera in Godot (registered polling asset, 1 ms tick) against the core-pro
# benchmark client (bench_client: one request at a time, no sleep, keeps its asset
# time moving while it waits). Per size: round trip, Godot's parts, and the RTF of
# the run (requests back to back, so every step that is not waiting renders).
# Usage: CORE_PRO_BUILD=<core-pro>/cmake-build [COUNT=300] [SIZES="640x480 1280x720"] bash examples/render_camera/run_bench.bash
set -u

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
EXAMPLE_DIR=${REPO_ROOT}/examples/render_camera
CORE_PRO_BUILD=${CORE_PRO_BUILD:?set CORE_PRO_BUILD to a hakoniwa-core-pro build directory}
GODOT_BIN=${GODOT_BIN:-/Applications/Godot_mono.app/Contents/MacOS/Godot}
COUNT=${COUNT:-300}
SIZES=${SIZES:-"0x0 640x480 1280x720 1920x1080"}
BIN=${CORE_PRO_BUILD}/examples/service_polling
HAKO_CMD=${CORE_PRO_BUILD}/sources/command/hako-cmd
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hako-godot-camera.XXXXXX")

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

echo "size,n,rtt_mean_ms,rtt_p99_ms,decode_ms,draw_ms,readback_ms,encode_ms,put_ms,sim_ms_per_frame,RTF"
for size in ${SIZES}; do
    width=${size%x*}
    height=${size#*x}
    bytes=$((width * height * 3))
    dir="${WORK_DIR}/${size}"
    mkdir -p "${dir}"
    # Same layout as core-pro examples/service_polling/bench.bash.
    cat > "${dir}/service.json" <<JSON
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
    "${BIN}/polling_conductor" > "${dir}/conductor.log" 2>&1 & PIDS+=($!)
    sleep 1
    "${GODOT_BIN}" --fixed-fps 1000 --resolution 320x240 --path "${EXAMPLE_DIR}" -- \
        "--service-json=${dir}/service.json" > "${dir}/godot.log" 2>&1 & PIDS+=($!)
    if ! wait_for "${dir}/godot.log" "SERVER registered" 30; then
        echo "${size},FAIL: Godot did not register (${dir})"
        cleanup
        continue
    fi
    "${BIN}/bench_client" "${dir}/service.json" "${size}" "${COUNT}" "${dir}/client.csv" > "${dir}/client.log" 2>&1 & CLIENT=$!
    PIDS+=(${CLIENT})
    sleep 1
    "${HAKO_CMD}" start > /dev/null 2>&1
    wait "${CLIENT}"
    "${HAKO_CMD}" stop > /dev/null 2>&1
    cleanup
    if grep -q "^ERROR" "${dir}/client.log"; then
        echo "${size},FAIL: $(grep '^ERROR' "${dir}/client.log" | head -1) (${dir})"
        continue
    fi
    python3 - "${size}" "${dir}" <<'PY'
import csv, re, statistics, sys
size, d = sys.argv[1], sys.argv[2]
rows = list(csv.DictReader(open(f"{d}/client.csv")))
rtt = sorted((int(r["response_in_ns"]) - int(r["send_ns"])) / 1e6 for r in rows)
seqs = {int(r["seq"]) for r in rows}
parts = {k: [] for k in ("decode", "draw", "readback", "encode", "put")}
for line in open(f"{d}/godot.log"):
    m = re.match(r"FRAME seq=(\d+) .*decode_us=(\d+) draw_us=(\d+) readback_us=(\d+) encode_us=(\d+) put_us=(\d+)", line)
    if m and int(m.group(1)) in seqs:
        for k, v in zip(parts, m.groups()[1:]):
            parts[k].append(int(v) / 1000)
sim = (int(rows[-1]["response_time_usec"]) - int(rows[0]["client_time_usec"])) / 1000
wall = (int(rows[-1]["response_in_ns"]) - int(rows[0]["send_ns"])) / 1e6
mean = lambda v: statistics.mean(v) if v else float("nan")
print(f"{size},{len(rows)},{mean(rtt):.3f},{rtt[int(len(rtt) * 0.99) - 1]:.3f},"
      + ",".join(f"{mean(v):.3f}" for v in parts.values())
      + f",{sim / len(rows):.2f},{sim / wall:.2f}")
PY
done
echo "logs: ${WORK_DIR}"
