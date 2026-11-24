#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <path/to/PrismDM.app>" >&2
    exit 1
fi

APP_BUNDLE="$1"
FRAMEWORKS_DIR="${APP_BUNDLE}/Frameworks"

if [ ! -d "${APP_BUNDLE}" ]; then
    echo "error: App bundle not found at ${APP_BUNDLE}" >&2
    exit 1
fi

# Strip any stale app-level _CodeSignature for clean unsigned IPA distribution
rm -rf "${APP_BUNDLE}/_CodeSignature"

if [ ! -d "${FRAMEWORKS_DIR}" ]; then
    echo "[normalize] No embedded Frameworks directory found in ${APP_BUNDLE}."
    exit 0
fi

PLIST_BUDDY="/usr/libexec/PlistBuddy"
NORMALIZED_COUNT=0

for FW in "${FRAMEWORKS_DIR}"/*.framework; do
    [ -d "${FW}" ] || continue
    FW_NAME="$(basename "${FW}")"
    FW_BIN_NAME="${FW_NAME%.framework}"
    FW_BIN="${FW}/${FW_BIN_NAME}"

    # Thin any multi-architecture framework binary strictly to arm64 for iPhone-only IPA
    if [ -f "${FW_BIN}" ] && command -v lipo >/dev/null 2>&1; then
        FW_ARCHS="$(lipo -archs "${FW_BIN}" 2>/dev/null || true)"
        if [ -n "${FW_ARCHS}" ] && [ "${FW_ARCHS}" != "arm64" ] && echo "${FW_ARCHS}" | grep -qw "arm64"; then
            echo "[normalize] ${FW_NAME}: thinning '${FW_ARCHS}' -> arm64"
            lipo -thin arm64 "${FW_BIN}" -output "${FW_BIN}.arm64"
            mv "${FW_BIN}.arm64" "${FW_BIN}"
        fi
    fi

    # Remove stale upstream signatures so AltStore/SideStore/Feather/Sideloadly re-sign cleanly
    rm -rf "${FW}/_CodeSignature"

    PLIST="${FW}/Info.plist"
    if [ -f "${PLIST}" ]; then
        if [ -x "${PLIST_BUDDY}" ]; then
            if "${PLIST_BUDDY}" -c "Print :MinimumOSVersion" "${PLIST}" >/dev/null 2>&1; then
                OLD_VER="$("${PLIST_BUDDY}" -c "Print :MinimumOSVersion" "${PLIST}")"
                if [ "${OLD_VER}" != "26.0" ]; then
                    echo "[normalize] ${FW_NAME}: MinimumOSVersion ${OLD_VER} -> 26.0"
                    "${PLIST_BUDDY}" -c "Set :MinimumOSVersion 26.0" "${PLIST}"
                fi
            else
                echo "[normalize] ${FW_NAME}: Adding MinimumOSVersion = 26.0"
                "${PLIST_BUDDY}" -c "Add :MinimumOSVersion string 26.0" "${PLIST}"
            fi
        fi
        if command -v plutil >/dev/null 2>&1; then
            plutil -lint "${PLIST}" >/dev/null
        fi
        NORMALIZED_COUNT=$((NORMALIZED_COUNT + 1))
    fi
done

echo "[normalize] Normalized ${NORMALIZED_COUNT} embedded framework(s) inside ${FRAMEWORKS_DIR}."
