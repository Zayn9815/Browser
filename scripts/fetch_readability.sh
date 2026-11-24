#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_FILE="${ROOT_DIR}/Packages/PrismModules/Sources/BrowserCore/Resources/Readability.js"
READABILITY_URL="https://raw.githubusercontent.com/mozilla/readability/0.6.0/Readability.js"
EXPECTED_SHA256="34dcab3d0832d0019f02990eed6b6124e029e8c32b9f0c6f2550544ff8dff174"

compute_sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

mkdir -p "$(dirname "${TARGET_FILE}")"

if [ -f "${TARGET_FILE}" ]; then
    EXISTING_SHA="$(compute_sha256 "${TARGET_FILE}")"
    if [ "${EXISTING_SHA}" = "${EXPECTED_SHA256}" ]; then
        echo "[readability] Verified existing Readability.js 0.6.0 (${EXISTING_SHA})."
        exit 0
    fi
fi

echo "[readability] Downloading Mozilla Readability.js 0.6.0..."
TMP_FILE="$(mktemp)"
trap 'rm -f "${TMP_FILE}"' EXIT

curl -fsSL --retry 3 --retry-delay 2 "${READABILITY_URL}" -o "${TMP_FILE}"
ACTUAL_SHA="$(compute_sha256 "${TMP_FILE}")"

if [ "${ACTUAL_SHA}" != "${EXPECTED_SHA256}" ]; then
    echo "error: Readability.js SHA-256 mismatch! expected=${EXPECTED_SHA256} actual=${ACTUAL_SHA}" >&2
    exit 1
fi

mv "${TMP_FILE}" "${TARGET_FILE}"
echo "[readability] Saved verified Readability.js 0.6.0 ($(wc -c < "${TARGET_FILE}" | tr -d ' ') bytes) -> ${TARGET_FILE}"
