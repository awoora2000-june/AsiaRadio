# App Store Connect checklist (Auradio iOS)

Use this before uploading a build. Copyright and privacy files live in the repo root and `/docs`.

## Identity

| Field | Value |
|-------|--------|
| Display name | Auradio |
| Bundle ID | `auradio.ios` |
| Version / Build | See `AsiaRadio/Info.plist` (currently 1.0.1 / 2) |
| Category | Music |
| Copyright (ASC App Information) | `2026 Jwoo` |
| Contact / Support email | support@jwoo.dev |

## Public URLs (must open in a browser as HTML)

GitHub Pages is configured for branch **`main`** / folder **`/`** (repo root).

| ASC field | URL |
|-----------|-----|
| Privacy Policy | https://awoora2000-june.github.io/AsiaRadio/privacy.html |
| Support | https://awoora2000-june.github.io/AsiaRadio/support.html |

Canonical files: root `privacy.html`, `support.html` (also mirrored under `docs/`).

In-app links: `AsiaRadio/Models/AppInfo.swift`.

## Legal / content

- [x] Proprietary `LICENSE` (Jwoo)
- [x] `ACKNOWLEDGEMENTS.md` (Radio Browser, broadcasters, assets)
- [x] `NSHumanReadableCopyright` in Info.plist
- [x] About → Legal & Acknowledgements
- [x] Privacy policy covers location, local notifications, purchases, content rights
- [x] App Privacy questionnaire answers documented below
- [x] Content Rights declaration text documented below

## Build

- [ ] Archive with **Release** (not Debug — Debug unlocks Premium)
- [ ] Team `8TTJ4963GC` is a paid Apple Developer Program team
- [x] `ITSAppUsesNonExemptEncryption` = NO (HTTPS only)
- [ ] IAP product `auradio_premium` ready in ASC
- [ ] Screenshots / description / keywords filled
- [x] No secrets in source (verified: no API keys / tokens in app target)

## Export compliance / age

- Encryption: exempt (standard HTTPS) as declared in Info.plist  
- Age rating: complete questionnaire (music streaming / infrequent unrestricted web)

---

## App Privacy questionnaire (copy into App Store Connect)

Aligned with `privacy.html` and `AsiaRadio/PrivacyInfo.xcprivacy`.

| ASC question | Answer |
|--------------|--------|
| Do you or your third-party partners collect data? | **No** — no account; favorites/settings stay on device. Optional location is used only on-device for list sort and is not uploaded. |
| Privacy Tracking (ATT) | **No** — `NSPrivacyTracking` = false |
| Data used to track user | **No** |
| Data linked to user | **No** (no user account) |
| Data types collected | **None** declared in Privacy Nutrition Labels for server-side collection. Optional **Location** is Precise Location, **App Functionality**, **not linked**, **not used for tracking**, processed on device only — if ASC forces a location row because of the permission string, choose: Purpose = App Functionality; Linked to identity = No; Used for tracking = No. |
| Purchases | Handled by Apple; app only checks entitlement locally via StoreKit. Do **not** declare Purchase History unless you send receipts to your own server (Auradio does not). |
| Product interaction / crash | Not collected by Auradio servers. |
| Third-party analytics / ads | **None** |

**Privacy Policy URL:** same as table above.

---

## Content Rights (App Store Connect)

Suggested response when asked whether you have rights to use third-party content:

> Auradio aggregates publicly available radio station metadata (names, tags, stream URLs, favicons) primarily via the Radio Browser open API and, where needed, official broadcaster endpoints (e.g. KBS, MBC, SBS, NHK-related sources) solely to resolve playable streams. The app does not host or redistribute broadcast audio files; playback connects to each station’s stream servers. Station logos, trademarks, and programming remain the property of their respective rights holders. Original app software, UI, and Auradio branding are owned by Jwoo.

ASC “Content Rights” checkbox: select that you have the rights to use the content in the app as described (metadata aggregation + stream linking), not that you own the broadcasts.

---

## Pre-upload verification log

| Check | Status |
|-------|--------|
| Commit legal/source updates to `main` | done (`40ef879`, merge `a1e1ebd`) |
| Push to `awoora2000-june/AsiaRadio` | done |
| GitHub Pages `/` (root) enabled | done (already on `main` / `/`) |
| Privacy/Support URLs return HTTP 200 HTML | verify after Pages rebuild |
| `Release` configuration build succeeds | done |
| Debug premium unlock not in Release (`#else false`) | done |
| Secrets scan clean | done |

### Still manual in App Store Connect / Xcode

- [ ] Paste Privacy & Support URLs into ASC App Information
- [ ] Fill App Privacy using the questionnaire table above
- [ ] Confirm Content Rights with the declaration above
- [ ] Archive **Release**, upload build, attach to version
- [ ] Confirm IAP `auradio_premium` + screenshots/description
- [ ] Confirm team `8TTJ4963GC` is paid Apple Developer Program
