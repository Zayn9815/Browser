#!/usr/bin/env bash
set -euo pipefail

case "${PLATFORM_NAME:-}" in
  iphoneos|iphonesimulator) ;;
  *) echo "[ytdlp-python] Skipping for PLATFORM_NAME=${PLATFORM_NAME:-unknown}"; exit 0 ;;
esac

DERIVED_PACKAGES="${BUILD_DIR%/Build/*}/SourcePackages"
CI_PACKAGES="${SRCROOT}/.build/SourcePackages"

SCRIPT_PATH=""
for candidate in \
    "${CI_PACKAGES}/checkouts/ytdlp-apple/scripts/install-python.sh" \
    "${DERIVED_PACKAGES}/checkouts/ytdlp-apple/scripts/install-python.sh"; do
  if [ -f "${candidate}" ]; then
    SCRIPT_PATH="${candidate}"
    break
  fi
done

if [ -z "${SCRIPT_PATH}" ]; then
  echo "error: ytdlp-apple/scripts/install-python.sh not found in ${CI_PACKAGES} or ${DERIVED_PACKAGES}" >&2
  exit 1
fi

XCF_PATH=""
for candidate in \
    "${CI_PACKAGES}/artifacts/ytdlp-apple/Python/Python.xcframework" \
    "${CI_PACKAGES}/artifacts/ytdlp-apple/Python.xcframework" \
    "${DERIVED_PACKAGES}/artifacts/ytdlp-apple/Python/Python.xcframework" \
    "${DERIVED_PACKAGES}/artifacts/ytdlp-apple/Python.xcframework"; do
  if [ -f "${candidate}/build/utils.sh" ]; then
    XCF_PATH="${candidate}"
    break
  fi
done

if [ -z "${XCF_PATH}" ]; then
  echo "error: Python.xcframework not found in SourcePackages artifacts" >&2
  exit 1
fi

echo "[ytdlp-python] Using script: ${SCRIPT_PATH}"
echo "[ytdlp-python] Using xcframework: ${XCF_PATH}"

export YTDLP_PYTHON_XCFRAMEWORK="${XCF_PATH}"
# On unsigned CI builds (CODE_SIGNING_ALLOWED=NO), EXPANDED_CODE_SIGN_IDENTITY is empty,
# while BeeWare's utils.sh unconditionally runs `codesign --sign "$EXPANDED_CODE_SIGN_IDENTITY"`.
# Use Apple's ad-hoc identity ("-") when unset; normalize_embedded_frameworks.sh strips _CodeSignature afterward.
if [ -z "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  export EXPANDED_CODE_SIGN_IDENTITY="-"
  export EXPANDED_CODE_SIGN_IDENTITY_NAME="${EXPANDED_CODE_SIGN_IDENTITY_NAME:-Ad-Hoc}"
else
  export EXPANDED_CODE_SIGN_IDENTITY_NAME="${EXPANDED_CODE_SIGN_IDENTITY_NAME:-${EXPANDED_CODE_SIGN_IDENTITY}}"
fi
export CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-${EXPANDED_CODE_SIGN_IDENTITY}}"
export CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
export CODE_SIGNING_REQUIRED="${CODE_SIGNING_REQUIRED:-NO}"

bash "${SCRIPT_PATH}"
