#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMODULE_DIR="${ROOT_DIR}/Vendor/SwiftyDownloadManager"
PATCH_FILE="${ROOT_DIR}/patches/sdmcore-browser-headers.patch"

if [ ! -f "${ROOT_DIR}/.gitmodules" ]; then
    echo "error: .gitmodules not found in ${ROOT_DIR}" >&2
    exit 1
fi

if [ ! -d "${SUBMODULE_DIR}/Packages/SDMCore" ]; then
    echo "[bootstrap] Initializing Vendor/SwiftyDownloadManager submodule..."
    git -C "${ROOT_DIR}" submodule update --init --recursive Vendor/SwiftyDownloadManager
fi

if [ ! -f "${PATCH_FILE}" ]; then
    echo "error: Missing required patch file ${PATCH_FILE}" >&2
    exit 1
fi

if git -C "${SUBMODULE_DIR}" apply --reverse --check "${PATCH_FILE}" 2>/dev/null; then
    echo "[bootstrap] sdmcore-browser-headers.patch is already applied."
elif git -C "${SUBMODULE_DIR}" apply --check "${PATCH_FILE}" 2>/dev/null; then
    echo "[bootstrap] Applying sdmcore-browser-headers.patch to Vendor/SwiftyDownloadManager..."
    git -C "${SUBMODULE_DIR}" apply "${PATCH_FILE}"
    echo "[bootstrap] Patch applied successfully."
else
    echo "error: Unable to apply ${PATCH_FILE} cleanly to ${SUBMODULE_DIR}" >&2
    exit 1
fi
