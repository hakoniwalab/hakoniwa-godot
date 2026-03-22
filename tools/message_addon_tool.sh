#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_ROOT="${REPO_ROOT}/third_party/hakoniwa-core-pro/hakoniwa-pdu-registry/pdu/godot_gd"
DEFAULT_TARGET_DIR="${REPO_ROOT}/addons/hakoniwa_msgs"

usage() {
  cat <<'EOF'
Usage:
  bash tools/message_addon_tool.sh list
  bash tools/message_addon_tool.sh sync [--packages PKG1;PKG2|all] [--target-dir DIR]
  bash tools/message_addon_tool.sh paths [--packages PKG1;PKG2|all] [--target-dir DIR]

Commands:
  list
    Print available generated GDScript message packages.

  sync
    Copy generated Godot GDScript message classes into addons/hakoniwa_msgs.

  paths
    Print the source and destination paths for the selected packages.

Examples:
  bash tools/message_addon_tool.sh list
  bash tools/message_addon_tool.sh sync --packages "std_msgs;hako_msgs"
  bash tools/message_addon_tool.sh sync --packages all
EOF
}

list_packages() {
  if [[ ! -d "${SOURCE_ROOT}" ]]; then
    echo "message source directory not found: ${SOURCE_ROOT}" >&2
    exit 1
  fi

  find "${SOURCE_ROOT}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
}

normalize_packages() {
  local raw="${1:-all}"
  if [[ "${raw}" == "all" ]]; then
    echo "all"
    return
  fi
  echo "${raw}" | tr ',' ';'
}

resolve_package_list() {
  local packages
  packages="$(normalize_packages "${1:-all}")"
  if [[ "${packages}" == "all" ]]; then
    list_packages
    return
  fi
  echo "${packages}" | tr ';' '\n' | sed '/^$/d'
}

normalize_gdscript_file() {
  local file_path="$1"
  local relative_path="${file_path#${REPO_ROOT}/}"
  local resource_path="res://${relative_path}"

  perl -0pi -e 's/static func from_dict\(d: Dictionary\) -> [^:]+:/static func from_dict(d: Dictionary):/g' "${file_path}"
  RESOURCE_PATH="${resource_path}" perl -0pi -e 'my $p = $ENV{"RESOURCE_PATH"}; s/var obj := [A-Za-z0-9_]+\.new\(\)/qq{var obj = load("$p").new()}/ge' "${file_path}"
  perl -0pi -e 's/var ([A-Za-z0-9_]+): [A-Za-z0-9_]+ = ([A-Za-z0-9_]+)\.new\(\)/var $1 = $2.new()/g' "${file_path}"
  perl -0pi -e 's/var ([A-Za-z0-9_]+): HakoPdu_[A-Za-z0-9_]+ =/var $1 =/g' "${file_path}"
  perl -0pi -e 's/var ([A-Za-z0-9_]+) = HakoPdu_[A-Za-z0-9_]+\.new\(\)/var $1 = null/g' "${file_path}"
}

normalize_package_scripts() {
  local package_dir="$1"
  while IFS= read -r gd_file; do
    [[ -z "${gd_file}" ]] && continue
    normalize_gdscript_file "${gd_file}"
  done < <(find "${package_dir}" -type f -name '*.gd' | sort)
}

sync_cmd() {
  local packages="all"
  local target_dir="${DEFAULT_TARGET_DIR}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --packages)
        packages="$2"
        shift 2
        ;;
      --target-dir)
        target_dir="$2"
        shift 2
        ;;
      *)
        echo "unknown option for sync: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  mkdir -p "${target_dir}"

  while IFS= read -r pkg; do
    [[ -z "${pkg}" ]] && continue
    local src_dir="${SOURCE_ROOT}/${pkg}"
    local dst_dir="${target_dir}/${pkg}"
    if [[ ! -d "${src_dir}" ]]; then
      echo "message package not found: ${src_dir}" >&2
      exit 1
    fi
    rm -rf "${dst_dir}"
    mkdir -p "${dst_dir}"
    cp -R "${src_dir}/." "${dst_dir}/"
    normalize_package_scripts "${dst_dir}"
    echo "synced: ${pkg}"
  done < <(resolve_package_list "${packages}")
}

paths_cmd() {
  local packages="all"
  local target_dir="${DEFAULT_TARGET_DIR}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --packages)
        packages="$2"
        shift 2
        ;;
      --target-dir)
        target_dir="$2"
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
    echo "  source: ${SOURCE_ROOT}/${pkg}"
    echo "  target: ${target_dir}/${pkg}"
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
    sync)
      sync_cmd "$@"
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
