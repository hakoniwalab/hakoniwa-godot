#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_DIST_DIR="${REPO_ROOT}/dist"
DEFAULT_RUNTIME_ADDON_DIR="${REPO_ROOT}/addons/hakoniwa"
DEFAULT_MSG_ADDON_DIR="${REPO_ROOT}/addons/hakoniwa_msgs"

usage() {
  cat <<'EOF'
Usage:
  bash tools/addon_artifact_tool.sh stage --platform PLATFORM --arch ARCH [options]
  bash tools/addon_artifact_tool.sh archive --platform PLATFORM --arch ARCH [options]
  bash tools/addon_artifact_tool.sh paths --platform PLATFORM --arch ARCH [options]

Commands:
  stage
    Create a staging directory containing addons/hakoniwa and, if present,
    addons/hakoniwa_msgs for the selected platform.

  archive
    Create the staging directory and then archive it as .tar.gz.

  paths
    Print the expected staging and archive paths.

Required:
  --platform PLATFORM   One of: macos, linux
  --arch ARCH           For example: arm64, x86_64

Options:
  --dist-dir DIR        Output directory for staged artifacts and archives
  --runtime-dir DIR     Source runtime addon directory; defaults to addons/hakoniwa
  --msgs-dir DIR        Source message addon directory; defaults to addons/hakoniwa_msgs
  --packages LIST       Codec packages to include; LIST is PKG1;PKG2 or all
  --artifact-name NAME  Override archive/staging base name

Examples:
  bash tools/addon_artifact_tool.sh stage --platform macos --arch arm64 --packages all
  bash tools/addon_artifact_tool.sh archive --platform linux --arch x86_64 --packages "hako_msgs;std_msgs"
EOF
}

normalize_packages() {
  local raw="${1:-all}"
  if [[ "${raw}" == "all" ]]; then
    echo "all"
    return
  fi
  echo "${raw}" | tr ',' ';'
}

resolve_library_extension() {
  case "$1" in
    macos) echo ".dylib" ;;
    linux) echo ".so" ;;
    *)
      echo "unsupported platform: $1" >&2
      exit 1
      ;;
  esac
}

resolve_artifact_name() {
  local platform="$1"
  local arch="$2"
  local override="${3:-}"
  if [[ -n "${override}" ]]; then
    echo "${override}"
  else
    echo "hakoniwa-godot-${platform}-${arch}"
  fi
}

copy_runtime_addon() {
  local runtime_dir="$1"
  local target_root="$2"
  local ext="$3"
  local packages="$4"

  if [[ ! -d "${runtime_dir}" ]]; then
    echo "runtime addon directory not found: ${runtime_dir}" >&2
    exit 1
  fi

  mkdir -p "${target_root}/addons/hakoniwa/bin"
  mkdir -p "${target_root}/addons/hakoniwa/codecs"
  mkdir -p "${target_root}/addons/hakoniwa/scripts"

  cp "${runtime_dir}/plugin.cfg" "${target_root}/addons/hakoniwa/"
  cp "${runtime_dir}/hakoniwa.gdextension" "${target_root}/addons/hakoniwa/"
  cp -R "${runtime_dir}/scripts/." "${target_root}/addons/hakoniwa/scripts/"

  if compgen -G "${runtime_dir}/bin/*${ext}" > /dev/null; then
    cp "${runtime_dir}/bin/"*"${ext}" "${target_root}/addons/hakoniwa/bin/"
  else
    echo "no runtime binary found for extension ${ext} in ${runtime_dir}/bin" >&2
    exit 1
  fi

  if [[ "${packages}" == "all" ]]; then
    find "${runtime_dir}/codecs" -maxdepth 1 -type f \( -name "*${ext}" -o -name "*.gdextension" \) -exec cp {} "${target_root}/addons/hakoniwa/codecs/" \;
  else
    while IFS= read -r pkg; do
      [[ -z "${pkg}" ]] && continue
      local lib_src="${runtime_dir}/codecs/${pkg}_codec${ext}"
      local gdext_src="${runtime_dir}/codecs/${pkg}_codec.gdextension"
      if [[ ! -f "${lib_src}" ]]; then
        echo "codec library not found: ${lib_src}" >&2
        exit 1
      fi
      if [[ ! -f "${gdext_src}" ]]; then
        echo "codec gdextension not found: ${gdext_src}" >&2
        exit 1
      fi
      cp "${lib_src}" "${target_root}/addons/hakoniwa/codecs/"
      cp "${gdext_src}" "${target_root}/addons/hakoniwa/codecs/"
    done < <(echo "${packages}" | tr ';' '\n')
  fi
}

copy_message_addon_if_present() {
  local msgs_dir="$1"
  local target_root="$2"

  if [[ -d "${msgs_dir}" ]]; then
    mkdir -p "${target_root}/addons/hakoniwa_msgs"
    cp -R "${msgs_dir}/." "${target_root}/addons/hakoniwa_msgs/"
  fi
}

stage_cmd() {
  local platform=""
  local arch=""
  local dist_dir="${DEFAULT_DIST_DIR}"
  local runtime_dir="${DEFAULT_RUNTIME_ADDON_DIR}"
  local msgs_dir="${DEFAULT_MSG_ADDON_DIR}"
  local packages="all"
  local artifact_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --platform) platform="$2"; shift 2 ;;
      --arch) arch="$2"; shift 2 ;;
      --dist-dir) dist_dir="$2"; shift 2 ;;
      --runtime-dir) runtime_dir="$2"; shift 2 ;;
      --msgs-dir) msgs_dir="$2"; shift 2 ;;
      --packages) packages="$2"; shift 2 ;;
      --artifact-name) artifact_name="$2"; shift 2 ;;
      *)
        echo "unknown option for stage: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [[ -z "${platform}" || -z "${arch}" ]]; then
    echo "--platform and --arch are required" >&2
    usage
    exit 1
  fi

  packages="$(normalize_packages "${packages}")"
  local ext
  ext="$(resolve_library_extension "${platform}")"
  local base_name
  base_name="$(resolve_artifact_name "${platform}" "${arch}" "${artifact_name}")"
  local stage_dir="${dist_dir}/${base_name}"

  rm -rf "${stage_dir}"
  mkdir -p "${stage_dir}"

  copy_runtime_addon "${runtime_dir}" "${stage_dir}" "${ext}" "${packages}"
  copy_message_addon_if_present "${msgs_dir}" "${stage_dir}"

  echo "${stage_dir}"
}

archive_cmd() {
  local platform=""
  local arch=""
  local dist_dir="${DEFAULT_DIST_DIR}"
  local runtime_dir="${DEFAULT_RUNTIME_ADDON_DIR}"
  local msgs_dir="${DEFAULT_MSG_ADDON_DIR}"
  local packages="all"
  local artifact_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --platform) platform="$2"; shift 2 ;;
      --arch) arch="$2"; shift 2 ;;
      --dist-dir) dist_dir="$2"; shift 2 ;;
      --runtime-dir) runtime_dir="$2"; shift 2 ;;
      --msgs-dir) msgs_dir="$2"; shift 2 ;;
      --packages) packages="$2"; shift 2 ;;
      --artifact-name) artifact_name="$2"; shift 2 ;;
      *)
        echo "unknown option for archive: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  local stage_dir
  stage_dir="$(stage_cmd --platform "${platform}" --arch "${arch}" --dist-dir "${dist_dir}" --runtime-dir "${runtime_dir}" --msgs-dir "${msgs_dir}" --packages "${packages}" --artifact-name "${artifact_name}")"
  local archive_path="${stage_dir}.tar.gz"
  tar -C "${dist_dir}" -czf "${archive_path}" "$(basename "${stage_dir}")"
  echo "${archive_path}"
}

paths_cmd() {
  local platform=""
  local arch=""
  local dist_dir="${DEFAULT_DIST_DIR}"
  local artifact_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --platform) platform="$2"; shift 2 ;;
      --arch) arch="$2"; shift 2 ;;
      --dist-dir) dist_dir="$2"; shift 2 ;;
      --artifact-name) artifact_name="$2"; shift 2 ;;
      *)
        echo "unknown option for paths: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [[ -z "${platform}" || -z "${arch}" ]]; then
    echo "--platform and --arch are required" >&2
    usage
    exit 1
  fi

  local base_name
  base_name="$(resolve_artifact_name "${platform}" "${arch}" "${artifact_name}")"
  echo "stage: ${dist_dir}/${base_name}"
  echo "archive: ${dist_dir}/${base_name}.tar.gz"
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  local cmd="$1"
  shift

  case "${cmd}" in
    stage) stage_cmd "$@" ;;
    archive) archive_cmd "$@" ;;
    paths) paths_cmd "$@" ;;
    -h|--help|help) usage ;;
    *)
      echo "unknown command: ${cmd}" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
