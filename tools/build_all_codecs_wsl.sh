#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

build_dir=""
generator="Visual Studio 17 2022"
arch="x64"
configuration="Debug"
toolchain_file=""
vcpkg_triplet="x64-windows"
boost_dir=""
godot_bin=""
tests="ON"
dependency_build="minimal"
packages="all"
skip_message_sync="false"
clean="false"

usage() {
  cat <<'EOF'
Usage:
  bash tools/build_all_codecs_wsl.sh [options]

Options:
  --build-dir DIR
  --generator NAME
  --arch x64
  --config Debug|Release
  --toolchain-file PATH
  --vcpkg-triplet NAME
  --boost-dir PATH
  --godot-bin PATH
  --tests ON|OFF
  --dependency-build minimal|full
  --packages PKG1;PKG2|all
  --skip-message-sync
  --clean
EOF
}

if ! command -v wslpath >/dev/null 2>&1; then
  echo "tools/build_all_codecs_wsl.sh requires WSL with wslpath available." >&2
  exit 1
fi

if ! command -v powershell.exe >/dev/null 2>&1; then
  echo "tools/build_all_codecs_wsl.sh requires powershell.exe in PATH." >&2
  exit 1
fi

POWERSHELL_SCRIPT_WIN="$(wslpath -w "${SCRIPT_DIR}/build_all_codecs.ps1")"

to_windows_path() {
  local path="$1"
  if [[ -z "${path}" ]]; then
    return
  fi
  wslpath -w "${path}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir)
      build_dir="$(to_windows_path "$2")"
      shift 2
      ;;
    --generator)
      generator="$2"
      shift 2
      ;;
    --arch)
      arch="$2"
      shift 2
      ;;
    --config)
      configuration="$2"
      shift 2
      ;;
    --toolchain-file)
      toolchain_file="$(to_windows_path "$2")"
      shift 2
      ;;
    --vcpkg-triplet)
      vcpkg_triplet="$2"
      shift 2
      ;;
    --boost-dir)
      boost_dir="$(to_windows_path "$2")"
      shift 2
      ;;
    --godot-bin)
      godot_bin="$(to_windows_path "$2")"
      shift 2
      ;;
    --tests)
      tests="$2"
      shift 2
      ;;
    --dependency-build)
      dependency_build="$2"
      shift 2
      ;;
    --packages)
      packages="$2"
      shift 2
      ;;
    --skip-message-sync)
      skip_message_sync="true"
      shift
      ;;
    --clean)
      clean="true"
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

cmd=(
  powershell.exe
  -NoProfile
  -ExecutionPolicy Bypass
  -File "${POWERSHELL_SCRIPT_WIN}"
  -Generator "${generator}"
  -Arch "${arch}"
  -Configuration "${configuration}"
  -VcpkgTriplet "${vcpkg_triplet}"
  -Tests "${tests}"
  -DependencyBuild "${dependency_build}"
  -Packages "${packages}"
)

if [[ -n "${build_dir}" ]]; then
  cmd+=(-BuildDir "${build_dir}")
fi

if [[ -n "${godot_bin}" ]]; then
  cmd+=(-GodotBin "${godot_bin}")
fi

if [[ -n "${toolchain_file}" ]]; then
  cmd+=(-ToolchainFile "${toolchain_file}")
fi

if [[ -n "${boost_dir}" ]]; then
  cmd+=(-BoostDir "${boost_dir}")
fi

if [[ "${skip_message_sync}" == "true" ]]; then
  cmd+=(-SkipMessageSync)
fi

if [[ "${clean}" == "true" ]]; then
  cmd+=(-Clean)
fi

"${cmd[@]}"
