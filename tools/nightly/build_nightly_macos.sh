#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

OUTPUT_ROOT="${REPO_ROOT}/artifacts/nightly"
RUNTIME_BASE=""
BINARY_SOURCE=""
SKIP_BOOTSTRAP=0
SKIP_BUILD=0

ARCH="$(uname -m)"
if [[ "${ARCH}" == "arm64" ]]; then
  CONFIGURE_PRESET="macos-arm64"
else
  CONFIGURE_PRESET="macos-x64"
fi
BUILD_PRESET="${CONFIGURE_PRESET}-release"

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
    --skip-bootstrap)
      SKIP_BOOTSTRAP=1
      shift
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

if [[ "$SKIP_BOOTSTRAP" -eq 0 ]]; then
  (
    cd "${REPO_ROOT}"
    ./bootstrap.sh
  )
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  cmake --preset "${CONFIGURE_PRESET}"
  cmake --build --preset "${BUILD_PRESET}"
fi

if [[ -z "${BINARY_SOURCE}" ]]; then
  BINARY_SOURCE="${REPO_ROOT}/build-${CONFIGURE_PRESET}/Release/ezQuake.app"
fi

if [[ ! -d "${BINARY_SOURCE}" ]]; then
  echo "Binary source missing (expected .app bundle): ${BINARY_SOURCE}" >&2
  exit 1
fi

PACKAGER="${REPO_ROOT}/tools/nightly/package_test_kit.py"
ARGS=(
  "${PACKAGER}"
  --platform macos
  --repo-root "${REPO_ROOT}"
  --output-root "${OUTPUT_ROOT}"
  --binary-source "${BINARY_SOURCE}"
  --launch-binary-relative "bin/ezQuake.app/Contents/MacOS/ezQuake"
)
if [[ -n "${RUNTIME_BASE}" ]]; then
  ARGS+=(--runtime-base "${RUNTIME_BASE}")
fi

if command -v python3 >/dev/null 2>&1; then
  python3 "${ARGS[@]}"
else
  python "${ARGS[@]}"
fi
