#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

OUTPUT_ROOT="${REPO_ROOT}/artifacts/nightly"
CONFIGURE_PRESET="dynamic"
BUILD_PRESET="dynamic-release"
RUNTIME_BASE=""
BINARY_SOURCE=""
SKIP_BUILD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-root)
      OUTPUT_ROOT="$2"
      shift 2
      ;;
    --configure-preset)
      CONFIGURE_PRESET="$2"
      shift 2
      ;;
    --build-preset)
      BUILD_PRESET="$2"
      shift 2
      ;;
    --runtime-base)
      RUNTIME_BASE="$2"
      shift 2
      ;;
    --binary-source)
      BINARY_SOURCE="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  cmake --preset "${CONFIGURE_PRESET}"
  cmake --build --preset "${BUILD_PRESET}"

  EXECUTABLE="$(echo "${REPO_ROOT}/build-${CONFIGURE_PRESET}/Release/ezquake"*)"
  (
    cd "${REPO_ROOT}"
    EXECUTABLE="${EXECUTABLE}" ./misc/appimage/appimage-manual_creation.sh
  )

  ARCH="$(uname -m)"
  APPIMAGE="${REPO_ROOT}/ezQuake-${ARCH}.AppImage"
  mkdir -p "${REPO_ROOT}/build-${CONFIGURE_PRESET}/Release"
  mv -f "${APPIMAGE}" "${REPO_ROOT}/build-${CONFIGURE_PRESET}/Release/ezQuake-${ARCH}.AppImage"
fi

if [[ -z "${BINARY_SOURCE}" ]]; then
  ARCH="$(uname -m)"
  BINARY_SOURCE="${REPO_ROOT}/build-${CONFIGURE_PRESET}/Release/ezQuake-${ARCH}.AppImage"
fi

if [[ ! -e "${BINARY_SOURCE}" ]]; then
  echo "Binary source missing: ${BINARY_SOURCE}" >&2
  exit 1
fi

PACKAGER="${REPO_ROOT}/tools/nightly/package_test_kit.py"
ARGS=(
  "${PACKAGER}"
  --platform linux
  --repo-root "${REPO_ROOT}"
  --output-root "${OUTPUT_ROOT}"
  --binary-source "${BINARY_SOURCE}"
  --launch-binary-relative "bin/$(basename "${BINARY_SOURCE}")"
)
if [[ -n "${RUNTIME_BASE}" ]]; then
  ARGS+=(--runtime-base "${RUNTIME_BASE}")
fi

if command -v python3 >/dev/null 2>&1; then
  python3 "${ARGS[@]}"
else
  python "${ARGS[@]}"
fi
