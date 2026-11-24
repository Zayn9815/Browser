<div align="center">

# PrismDM

**Flagship iPhone-Only Browser, Multi-Thread Parallel Download Manager, Universal Video Player & Biometric Vault**

[![Platform](https://img.shields.io/badge/Platform-iPhone%20arm64%20Only-crimson?style=for-the-badge&logo=apple)](https://github.com/Zayn9815/Browser)
[![iOS](https://img.shields.io/badge/iOS-26.0%2B-0A84FF?style=for-the-badge)](https://github.com/Zayn9815/Browser)
[![Swift](https://img.shields.io/badge/Swift-6.0%20%2F%206.2-FA7343?style=for-the-badge&logo=swift)](https://github.com/Zayn9815/Browser)
[![UI](https://img.shields.io/badge/UI-iOS%2026%20Liquid%20Glass-32D74B?style=for-the-badge)](https://github.com/Zayn9815/Browser)

*Built for maximum throughput, zero-clutter full-screen browsing, and strict on-device privacy.*

</div>

---

## Highlights

- **True Parallel Multi-Thread Downloader (HTTP & HLS)**
  - **Direct Files (`SDMCore` / `libcurl` + `URLSession`)**: Splits every range-capable file across **1–16 concurrent byte-range chunks** (default **8**). Automatically performs a lightweight `Range: bytes=0-0` probe when CDNs omit `Accept-Ranges` or `Content-Length` on `HEAD` so total file size and multi-range chunking unlock immediately.
  - **Two-Stage Parallel Chunked HLS (`.m3u8`) Engine**: Parses master & media playlists (`EXT-X-MAP`, relative URLs, `EXT-X-KEY` AES-128), downloads `.ts`/`.m4s` segments concurrently across **N parallel workers** with disk-backed resume and browser session headers (`Cookie`, `User-Agent`, `Referer`, `Origin`), then remuxes locally at NVMe speed via in-process `Libavformat`/`Libavcodec` (`-c copy`, `aac_adtstoasc`) into a playable `.mp4`.
  - **Live Telemetry**: Segmented per-chunk progress bars, full `downloaded / total` byte ratios, and EMA-smoothed live ETA (`~38s left`, `~2m 14s left`) throttled cleanly at 6 Hz.
  - **Default Downloader Selector**: Choose `PrismDM Multi-Thread (Default)`, `iOS Native (URLSession)`, or `Ask Every Time` in Settings.

- **Full-Screen Chrome, Swipeable Omnibox & On-Device Translation**
  - **Zero Permanent Bottom Tab Bar**: Maximizes webpage viewport. `Downloads`, `Vault`, and `Settings` open as instant native sheets from the **3-Dot (`•••`) Menu** or Start Page.
  - **User-Selectable Search Bar Position**: Anchor at the **Bottom** (default, with ergonomic `safeAreaInsets.bottom + 12pt` Home-bar clearance) or **Top** (with automatic WebView top inset).
  - **Swipe-to-Switch Tabs**: Swipe left or right directly on the floating address capsule with tactile haptic feedback.
  - **On-Device Page Translation**: Powered by Apple's native `Translation` framework (`TranslationSession`) with in-place DOM translation, instant **Show Original**, and one-tap **Google Translate** fallback.

- **Professional Start Page & 7-Theme Liquid Glass Suite**
  - **Editable Speed Dial Grid**: 4-column shortcuts grid with 8 defaults, cached favicons, brand-colored monograms, add/edit/reorder/remove, and Google Sign-In status pill.
  - **7 Curated Themes**: *Crimson Liquid Glass* (default), *iPhone Duo*, *Glacier Liquid Glass*, *Anodized Obsidian*, *Sahara Sand*, *Classic Stock*, and *Frost Light* — all audited for WCAG AA+ text contrast.
  - **Start Page Wallpapers & 7 Alternate App Icons**: Curated static gradients, custom photo picker, and 7 matching PrismDM geometric prism app icons switchable live in **Settings → Themes & Appearance**.

- **Brave-Style YouTube Ad-Free Shield & Offline AdBlock**
  - **Offline Sharded WebKit Content Blocker**: EasyList, EasyPrivacy, and dedicated YouTube network/cosmetic shards compiled at build time (`<= 125,000` rules/shard, zero unscoped wildcard blockers).
  - **In-Page YouTube Ad Shield**: `.atDocumentStart` JSON/fetch/`ytInitialPlayerResponse` ad-pruning + cosmetic CSS + zero-polling `MutationObserver` auto-skip.

- **Universal Video Player (`PrismPlayer`)**
  - Dual-engine playback: hardware `AVPlayer` for MP4/HLS + `libmpv` (`VideoToolbox` + `CAMetalLayer`) for MKV, WebM, AVI, FLV, and ASS/SSA subtitles.
  - Respects physical phone orientation and iOS Portrait Orientation Lock by default (never forces unwanted landscape tilt).

- **Dual-Space Biometric Vault (`Files Vault` & `Private Vault`)**
  - **Files Vault** (`Documents/Vault`): Exposed to the iOS Files app.
  - **Private Vault** (`ApplicationSupport/PrivateVault`): Hidden from Files & iCloud backups (`isExcludedFromBackup = true`), gated by Face ID / Touch ID / Passcode + custom PIN.
  - **Import & Atomic Cross-Vault Move**: Stream large photos & 4K videos directly to disk via `PhotosPicker` (`FileRepresentation`, zero RAM spike), import from iOS Files, optionally delete original Photos copies when importing into Private Vault, and atomically move items between `Files Vault` and `Private Vault`.
  - Built-in `ZIPFoundation` archive compression & path-traversal-safe extraction.

- **Built-In Diagnostics & Offline Crash Hub**
  - Powered by `kstenerud/KSCrash` (100% local offline mode — zero telemetry) and a rolling 2 MB `PrismLogCenter` with automatic privacy redaction (`Cookie`, `Authorization`, `Bearer`, PINs, PrivateVault paths, and Incognito URLs).
  - Inspect **All Logs**, **Errors & Warnings**, and **Crash Logs** with 1-tap **Copy for Antigravity** and `.log`/`.crash` sharing.

---

## Architecture

PrismDM is structured as a modular Swift 6 package (`Packages/PrismModules`) wired into a lightweight iPhone-only app shell (`App/`):

```text
PrismDM
├── App/                            # iPhone-only SwiftUI App entry, AppDelegate, Info.plist, Assets
├── Packages/PrismModules/
│   ├── Sources/PrismCore/          # 7-Theme Engine, Wallpapers, Icons, PrismLogCenter, KSCrash Manager
│   ├── Sources/AdBlockEngine/      # Offline Sharded Content Blocker + YouTubeAdShield.user.js
│   ├── Sources/BrowserCore/        # WebViewLRUPool, FloatingOmniboxBar, StartPageView, Translation, Settings
│   ├── Sources/MediaInterceptor/   # Cross-frame HLS/MP4 sniffer & fullscreen handoff bridge
│   ├── Sources/ParallelDownloader/ # SDMCore (libcurl/URLSession), Two-Stage Parallel HLS Engine, EMA ETA
│   ├── Sources/PrismPlayer/        # AVPlayer + libmpv (VideoToolbox/Metal) universal player & orientation
│   └── Sources/VaultManager/       # Files Vault / Private Vault, Biometrics, Photos/Files Import, ZIPFoundation
├── patches/                        # Idempotent SDMCore browser headers + Range:0-0 probe patch
├── scripts/                        # Icon generator, AdBlock shard compiler, framework normalizer, IPA verifier
└── .github/workflows/build-ipa.yml # Automated macos-26 unsigned iPhone arm64 IPA CI pipeline
```

---

## Building Locally or via GitHub Actions

> **Platform Constraint**: PrismDM is strictly **iPhone-only (`arm64` `iphoneos`, `IPHONEOS_DEPLOYMENT_TARGET = 26.0`, `TARGETED_DEVICE_FAMILY = "1"`, `SUPPORTS_MACCATALYST = NO`)**.

### Automated CI (Recommended)
Every push to `main` triggers [`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml) on `macos-26`:
1. Bootstraps `Vendor/SwiftyDownloadManager` and applies `patches/sdmcore-browser-headers.patch`.
2. Generates all 7 themed PrismDM `.appiconset` variants + preview thumbnails (`scripts/generate_app_icon.swift`).
3. Compiles offline EasyList, EasyPrivacy, and YouTube Ad Shield WebKit JSON shards (`scripts/build_adblock_rules.swift`).
4. Generates `PrismDM.xcodeproj` via `xcodegen`, builds the unsigned Release `iphoneos arm64` `.app`, normalizes embedded frameworks, packages `PrismDM-iOS26-arm64-unsigned.ipa`, and hard-verifies every required framework, certificate bundle, adblock shard, and alternate app icon via `scripts/verify_ipa_payload.sh`.

### Local macOS Build
```bash
git submodule update --init --recursive
bash scripts/bootstrap_submodules.sh
swift scripts/generate_app_icon.swift
swift scripts/build_adblock_rules.swift
xcodegen generate
xcodebuild -project PrismDM.xcodeproj -scheme PrismDM -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

---

## Privacy & Open-Source Attributions

PrismDM performs **zero analytics, zero telemetry, and zero remote crash uploads**. All ad-blocking rules, page translations, logs, crash reports, and vault files remain strictly on-device.

- **SwiftyDownloadManager (`SDMCore` & `CurlBinary`)** — FSL-1.1-MIT (libcurl, OpenSSL, Mozilla NSS CA Bundle)
- **FFmpegKit & libmpv (`kingslay/FFmpegKit`)** — LGPL-2.1-or-later / MIT / BSD
- **KSCrash (`kstenerud/KSCrash`)** — MIT License
- **ZIPFoundation** — MIT License
- **Mozilla Readability.js** — Apache-2.0 / MPL-2.0
- **EasyList & EasyPrivacy** — GPL-3.0 / CC-BY-SA-3.0

See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for full license texts.
