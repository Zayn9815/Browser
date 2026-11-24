# Third-Party Open Source Notices — PrismDM

PrismDM is an independent iPhone-only browser and download manager. It is not affiliated with, endorsed by, or sponsored by any upstream project listed below. No brand assets, app icons, trademarks, or visual identities from upstream repositories are bundled or redistributed in PrismDM.

---

## 1. SwiftyDownloadManager (`SDMCore` & `CurlBinary`)
- **Upstream Repository**: https://github.com/Kyle-Ye/SwiftyDownloadManager
- **Scope Used**: Exclusively the `Packages/SDMCore` and `Packages/CurlBinary` iOS `arm64` library packages (excluding macOS targets, browser extensions, and all visual/brand assets listed in upstream `BRANDING.md`).
- **License**: Functional Source License, Version 1.1, MIT Future License (`FSL-1.1-MIT`)
- **Copyright**: Copyright 2026 Kyle Ye. Full license text is preserved at `Vendor/SwiftyDownloadManager/LICENSE.md`.
- **Bundled Subcomponents in `SDMCore` / `CurlBinary`**:
  - **libcurl** (`curl-apple` 8.21.0) — curl License (MIT/X derivate)
  - **OpenSSL / BoringSSL** — Apache License 2.0 / OpenSSL License
  - **Mozilla NSS CA Certificate Bundle (`cacert.pem`)** — Mozilla Public License 2.0 (`MPL-2.0`)

---

## 2. FFmpegKit & libmpv (`kingslay/FFmpegKit` 9.0.2)
- **Upstream Repository**: https://github.com/kingslay/FFmpegKit
- **Scope Used**: iOS `arm64` `Libavformat`, `Libavcodec`, `Libavutil`, `Libswresample`, `Libswscale`, `Libavfilter`, `libmpv`, `libass`, `libssl`, and `libcrypto` XCFrameworks.
- **License**: GNU Lesser General Public License v2.1+ (`LGPL-2.1-or-later`) for FFmpeg/libmpv libraries; MIT/BSD/ISC/Apache-2.0 for constituent codec and rendering libraries (`libdav1d`, `libopus`, `libfreetype`, `libharfbuzz`, `libfribidi`, `lcms2`, `MoltenVK`, `OpenSSL`).

---

## 3. ZIPFoundation (`0.9.21`)
- **Upstream Repository**: https://github.com/weichsel/ZIPFoundation
- **License**: MIT License
- **Copyright**: Copyright (c) 2017–2026 Thomas Zoechling (https://www.peakstep.com)

---

## 4. Mozilla Readability (`Readability.js` 0.6.0)
- **Upstream Repository**: https://github.com/mozilla/readability
- **License**: Apache License 2.0 (`Apache-2.0`)
- **Copyright**: Copyright (c) 2010 Arc90 Inc / Mozilla Corporation

---

## 5. Offline Ad & Tracker Filter Lists (EasyList & EasyPrivacy)
- **Upstream Sources**:
  - EasyList: https://easylist.to/easylist/easylist.txt
  - EasyPrivacy: https://easylist.to/easylist/easyprivacy.txt
- **License**: Dual-licensed under GNU General Public License v3.0 (`GPL-3.0`) and Creative Commons Attribution-ShareAlike 3.0 Unported (`CC-BY-SA-3.0`).
- **Usage**: Fetched, converted to Apple WebKit Content Blocker JSON, and sharded at build time for offline `WKContentRuleListStore` execution.
