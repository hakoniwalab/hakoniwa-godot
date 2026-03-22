#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REGISTRY_DIR="${REPO_ROOT}/third_party/hakoniwa-core-pro/hakoniwa-pdu-registry/pdu/godot_cpp"

DEFAULT_BUILD_DIR="${REPO_ROOT}/build"
DEFAULT_GODOT_BIN="/Applications/Godot_mono.app/Contents/MacOS/Godot"

usage() {
  cat <<'EOF'
Usage:
  tools/codec_plugin_tool.sh list
  tools/codec_plugin_tool.sh configure [--build-dir DIR] [--packages PKG1;PKG2|all] [--godot-bin PATH] [--tests ON|OFF]
  tools/codec_plugin_tool.sh build [--build-dir DIR] [--target TARGET]
  tools/codec_plugin_tool.sh test [--build-dir DIR]
  tools/codec_plugin_tool.sh paths [--build-dir DIR] [--packages PKG1;PKG2|all]

Commands:
  list
    Print available codec packages from hakoniwa-pdu-registry.

  configure
    Configure CMake so codec plugin sources and .gdextension files are generated.
    This is the "plugin creation" step for package-specific shared libraries.

  build
    Build the configured targets.

  test
    Run ctest for the configured build directory.

  paths
    Print the expected addon output paths for the selected packages.

Examples:
  tools/codec_plugin_tool.sh list
  tools/codec_plugin_tool.sh configure --packages "hako_msgs;std_msgs"
  tools/codec_plugin_tool.sh build --target hako_msgs_codec
  tools/codec_plugin_tool.sh test
EOF
}

list_packages() {
  if [[ ! -d "${REGISTRY_DIR}" ]]; then
    echo "registry directory not found: ${REGISTRY_DIR}" >&2
    exit 1
  fi

  find "${REGISTRY_DIR}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
}

normalize_packages() {
  local raw="${1:-hako_msgs}"
  if [[ "${raw}" == "all" ]]; then
    echo "all"
    return
  fi
  echo "${raw}" | tr ',' ';'
}

resolve_package_list() {
  local packages
  packages="$(normalize_packages "${1:-hako_msgs}")"
  if [[ "${packages}" == "all" ]]; then
    list_packages
    return
  fi
  echo "${packages}" | tr ';' '\n' | sed '/^$/d'
}

configure_cmd() {
  local build_dir="${DEFAULT_BUILD_DIR}"
  local packages="hako_msgs"
  local godot_bin="${DEFAULT_GODOT_BIN}"
  local tests="ON"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --build-dir)
        build_dir="$2"
        shift 2
        ;;
      --packages)
        packages="$2"
        shift 2
        ;;
      --godot-bin)
        godot_bin="$2"
        shift 2
        ;;
      --tests)
        tests="$2"
        shift 2
        ;;
      *)
        echo "unknown option for configure: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  packages="$(normalize_packages "${packages}")"

  cmake -S "${REPO_ROOT}" -B "${build_dir}" \
    -DHAKONIWA_GODOT_CODEC_PACKAGES="${packages}" \
    -DHAKONIWA_GODOT_EXECUTABLE="${godot_bin}" \
    -DHAKONIWA_GODOT_BUILD_TESTS="${tests}"
}

build_cmd() {
  local build_dir="${DEFAULT_BUILD_DIR}"
  local target=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --build-dir)
        build_dir="$2"
        shift 2
        ;;
      --target)
        target="$2"
        shift 2
        ;;
      *)
        echo "unknown option for build: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [[ -n "${target}" ]]; then
    cmake --build "${build_dir}" -j4 --target "${target}"
  else
    cmake --build "${build_dir}" -j4
  fi
}

test_cmd() {
  local build_dir="${DEFAULT_BUILD_DIR}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --build-dir)
        build_dir="$2"
        shift 2
        ;;
      *)
        echo "unknown option for test: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  ctest --test-dir "${build_dir}" --output-on-failure
}

paths_cmd() {
  local build_dir="${DEFAULT_BUILD_DIR}"
  local packages="hako_msgs"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --build-dir)
        build_dir="$2"
        shift 2
        ;;
      --packages)
        packages="$2"
        shift 2
        ;;
      *)
        echo "unknown option for paths: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  while IFS= read -r pkg; do
    [[ -z "${pkg}" ]] && continue
    echo "package: ${pkg}"
    echo "  generated cpp: ${build_dir}/native/generated/${pkg}/${pkg}_codec_plugin.cpp"
    echo "  generated init: ${build_dir}/native/generated/${pkg}/${pkg}_codec_plugin_init.cpp"
    echo "  addon library: ${REPO_ROOT}/addons/hakoniwa/codecs/${pkg}_codec"
    echo "  addon gdextension: ${REPO_ROOT}/addons/hakoniwa/codecs/${pkg}_codec.gdextension"
  done < <(resolve_package_list "${packages}")
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  local cmd="$1"
  shift

  case "${cmd}" in
    list)
      list_packages
      ;;
    configure)
      configure_cmd "$@"
      ;;
    build)
      build_cmd "$@"
      ;;
    test)
      test_cmd "$@"
      ;;
    paths)
      paths_cmd "$@"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      echo "unknown command: ${cmd}" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
