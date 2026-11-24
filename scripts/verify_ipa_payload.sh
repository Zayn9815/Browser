#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <path/to/PrismDM.app>" >&2
    exit 1
fi

APP_BUNDLE="$1"
APP_BINARY="${APP_BUNDLE}/PrismDM"
APP_PLIST="${APP_BUNDLE}/Info.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

fail() {
    echo "error: $1" >&2
    exit 1
}

[ -d "${APP_BUNDLE}" ] || fail "App bundle missing: ${APP_BUNDLE}"
[ -f "${APP_BINARY}" ] || fail "Main executable missing: ${APP_BINARY}"
[ -f "${APP_PLIST}" ] || fail "Info.plist missing: ${APP_PLIST}"

# 1. Verify arm64-only Mach-O executable
ARCHS="$(lipo -archs "${APP_BINARY}")"
echo "[verify] Binary architectures: ${ARCHS}"
[ "${ARCHS}" = "arm64" ] || fail "Expected arm64-only Mach-O binary, found '${ARCHS}'"

# 2. Verify strict iPhone-only Info.plist keys
DEVICE_FAMILY="$("${PLIST_BUDDY}" -c "Print :UIDeviceFamily" "${APP_PLIST}" | tr -d ' \n')"
echo "[verify] UIDeviceFamily: ${DEVICE_FAMILY}"
echo "${DEVICE_FAMILY}" | grep -q "Array{1}" || fail "UIDeviceFamily must be [1] (iPhone-only), got ${DEVICE_FAMILY}"

REQUIRES_IOS="$("${PLIST_BUDDY}" -c "Print :LSRequiresIPhoneOS" "${APP_PLIST}")"
echo "[verify] LSRequiresIPhoneOS: ${REQUIRES_IOS}"
[ "${REQUIRES_IOS}" = "true" ] || fail "LSRequiresIPhoneOS must be true"

APP_MIN_OS="$("${PLIST_BUDDY}" -c "Print :MinimumOSVersion" "${APP_PLIST}")"
echo "[verify] App MinimumOSVersion: ${APP_MIN_OS}"
[ "${APP_MIN_OS}" = "26.0" ] || fail "Expected App MinimumOSVersion 26.0, found ${APP_MIN_OS}"

# 3. Verify compiled Assets.car containing AppIcon
ASSETS_CAR="${APP_BUNDLE}/Assets.car"
[ -s "${ASSETS_CAR}" ] || fail "Compiled Assets.car is missing or empty"
if command -v assetutil >/dev/null 2>&1; then
    assetutil --info "${ASSETS_CAR}" | grep -q '"Name" : "AppIcon"' || fail "AppIcon not found inside compiled Assets.car"
    echo "[verify] Verified AppIcon present inside Assets.car ($(wc -c < "${ASSETS_CAR}" | tr -d ' ') bytes)."
fi

# 4. Verify bundled SDMCore CA certificate bundle (cacert.pem)
CACERT_PATH="$(find "${APP_BUNDLE}" -name 'cacert.pem' -print -quit)"
[ -n "${CACERT_PATH}" ] && [ -s "${CACERT_PATH}" ] || fail "Bundled SDMCore cacert.pem is missing"
echo "[verify] Found cacert.pem: ${CACERT_PATH}"

# 5. Verify embedded FFmpegKit + libmpv frameworks & normalized MinimumOSVersion
FRAMEWORKS_DIR="${APP_BUNDLE}/Frameworks"
[ -d "${FRAMEWORKS_DIR}" ] || fail "Embedded Frameworks directory missing"

for REQUIRED_FW in Libavformat.framework Libavcodec.framework Libavutil.framework libmpv.framework libssl.framework libcrypto.framework; do
    FW_PATH="${FRAMEWORKS_DIR}/${REQUIRED_FW}"
    [ -d "${FW_PATH}" ] || fail "Required embedded framework missing: ${REQUIRED_FW}"
    FW_MIN_OS="$("${PLIST_BUDDY}" -c "Print :MinimumOSVersion" "${FW_PATH}/Info.plist")"
    [ "${FW_MIN_OS}" = "26.0" ] || fail "${REQUIRED_FW} MinimumOSVersion is ${FW_MIN_OS}, expected 26.0"
done

READABILITY_PATH="$(find "${APP_BUNDLE}" -name 'Readability.js' -print -quit)"
[ -n "${READABILITY_PATH}" ] && [ -s "${READABILITY_PATH}" ] || fail "Bundled Mozilla Readability.js is missing"
echo "[verify] Found Readability.js: ${READABILITY_PATH}"

for FW in "${FRAMEWORKS_DIR}"/*.framework; do
    [ -d "${FW}" ] || continue
    [ ! -d "${FW}/_CodeSignature" ] || fail "Stale _CodeSignature remains in ${FW}"
    if [ -f "${FW}/Info.plist" ]; then
        FW_MIN_OS="$("${PLIST_BUDDY}" -c "Print :MinimumOSVersion" "${FW}/Info.plist")"
        [ "${FW_MIN_OS}" = "26.0" ] || fail "$(basename "${FW}") MinimumOSVersion is ${FW_MIN_OS}, expected 26.0"
    fi
done
echo "[verify] Verified embedded FFmpegKit / libmpv frameworks and MinimumOSVersion=26.0."

# 6. Verify AdBlockShards manifest and shards
ADBLOCK_MANIFEST="${APP_BUNDLE}/AdBlockShards/manifest.json"
[ -s "${ADBLOCK_MANIFEST}" ] || fail "Bundled AdBlockShards/manifest.json missing or empty"
python3 - "${ADBLOCK_MANIFEST}" "${APP_BUNDLE}/AdBlockShards" <<'PY'
import json, os, sys
manifest_path, shard_dir = sys.argv[1], sys.argv[2]
with open(manifest_path, "r", encoding="utf-8") as f:
    manifest = json.load(f)
shards = manifest.get("shards", [])
assert len(shards) >= 2, f"Expected at least 2 adblock shards, found {len(shards)}"
total = 0
for s in shards:
    p = os.path.join(shard_dir, s["filename"])
    assert os.path.isfile(p) and os.path.getsize(p) > 0, f"Missing shard file {p}"
    with open(p, "r", encoding="utf-8") as sf:
        rules = json.load(sf)
    assert isinstance(rules, list) and 0 < len(rules) <= 150000, f"Invalid rule count {len(rules)} in {p}"
    total += len(rules)
print(f"[verify] Verified {len(shards)} AdBlock shards totaling {total} rules.")
PY

# 7. Verify non-trivial bundle size (> 15 MB with native FFmpeg/libmpv/libcurl)
BUNDLE_KB="$(du -sk "${APP_BUNDLE}" | awk '{print $1}')"
echo "[verify] Total PrismDM.app payload size: $((BUNDLE_KB / 1024)) MB (${BUNDLE_KB} KB)"
[ "${BUNDLE_KB}" -ge 15360 ] || fail "PrismDM.app payload unexpectedly small (${BUNDLE_KB} KB < 15360 KB)"

echo "[verify] ALL iPhone arm64 IPA payload integrity checks PASSED."
