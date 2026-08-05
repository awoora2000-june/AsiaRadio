# Auradio (iOS)

Asia and world radio streaming app for iPhone. Station metadata and stream URLs come from the [Radio Browser](https://www.radio-browser.info/) open API, with extra resolvers for major Korean and Japanese broadcasters.

Android port: sibling project [`AuradioAndroid`](../AuradioAndroid).

**Copyright © 2026 Jwoo. All rights reserved.** See [`LICENSE`](LICENSE) and [`ACKNOWLEDGEMENTS.md`](ACKNOWLEDGEMENTS.md).

## Requirements

- Xcode 15 or later
- iOS 17.0 or later
- Physical iPhone recommended (background playback, location-based sort)
- Apple Developer Program (paid) for App Store upload

## Getting Started

1. Open `AsiaRadio.xcodeproj` in Xcode.
2. Select your Team under **Signing & Capabilities** (team ID used for store: `8TTJ4963GC`).
3. Build and run on a device or simulator (⌘R).

If the debugger fails with `already being debugged`, stop the run, force-quit the app, quit Xcode, and run again.

## Features

### Tabs (5)

| Tab | Description |
|-----|-------------|
| **Channels** | All stations from 24 countries; sort by **Default** or **Nearby** |
| **Favorites** | Saved stations grouped by country |
| **Region** | Continent → country → station list |
| **Recent** | Last played stations (up to 20) |
| **Popular** | Top-voted stations per country |

### Playback

- Tap a row to play; mini player at the bottom, full player on tap
- Global search: name, frequency, tags, language, country
- **⋯ menu** on each row: Favorite, Startup Channel, Info
- Background audio, lock screen / Control Center metadata

### Settings

- **Sleep Timer** (Premium) — Duration (per-weekday end times) or End Time
- **Wake Radio** (Premium) — auto-play Startup Channel on set weekdays/times
- **Startup Channel** (Premium) — optional auto-play on launch
- App info, privacy, support, legal acknowledgements

## Supported Regions

**5 continents · 24 countries**

| Continent | Countries |
|-----------|-----------|
| Asia | 🇰🇷 Korea · 🇯🇵 Japan · 🇨🇳 China · 🇻🇳 Vietnam · 🇹🇭 Thailand · 🇵🇭 Philippines · 🇮🇩 Indonesia · 🇲🇾 Malaysia · 🇸🇬 Singapore · 🇮🇳 India · 🇹🇼 Taiwan · 🇭🇰 Hong Kong |
| Americas | 🇺🇸 United States · 🇨🇦 Canada |
| Europe | 🇫🇷 France · 🇩🇪 Germany · 🇪🇸 Spain · 🇷🇺 Russia |
| Oceania | 🇦🇺 Australia |
| Africa | 🇿🇦 South Africa · 🇪🇬 Egypt · 🇳🇬 Nigeria · 🇲🇦 Morocco · 🇰🇪 Kenya |

## Project Structure

```
AsiaRadio/
├── AsiaRadio/                 # App target (display name: Auradio)
│   ├── Models/AppInfo.swift   # Name, copyright, privacy/support URLs
│   ├── Services/              # Player, API, premium, wake, stores
│   ├── Views/                 # Tabs + Settings (AboutContentView)
│   ├── Info.plist             # Includes NSHumanReadableCopyright
│   └── PrivacyInfo.xcprivacy
├── privacy.html / support.html
├── docs/                      # GitHub Pages source + APP_STORE_CHECKLIST.md
├── LICENSE
├── ACKNOWLEDGEMENTS.md
└── scripts/generate_icons.swift
```

## Legal & Privacy URLs

| Document | Path | Public URL (GitHub Pages, `main` / root) |
|----------|------|------------------------------------------|
| Privacy | `privacy.html` | https://awoora2000-june.github.io/AsiaRadio/privacy.html |
| Support | `support.html` | https://awoora2000-june.github.io/AsiaRadio/support.html |

Pages is already enabled for this repo (`main` / `/`). Keep root `privacy.html` and `support.html` in sync when editing policy text.

App Store submission steps: [`docs/APP_STORE_CHECKLIST.md`](docs/APP_STORE_CHECKLIST.md).

## Build & Release

| Item | Value |
|------|-------|
| Product / display name | Auradio |
| Bundle ID | `auradio.ios` |
| Version | 1.0.1 (2) |
| Min iOS | 17.0 |
| IAP | `auradio_premium` |

```bash
xcodebuild -scheme AsiaRadio -destination 'generic/platform=iOS' -configuration Release build
```

Archive in Xcode with **Release**, then upload to App Store Connect.

**Important:** Debug builds unlock Premium for testing (`PremiumManager`). Never archive Debug for the store.

## Data Sources

See [`ACKNOWLEDGEMENTS.md`](ACKNOWLEDGEMENTS.md).

- [Radio Browser](https://www.radio-browser.info/) — station list, tags, geo, stream URLs
- Official broadcaster endpoints — KBS / MBC / SBS (KR), NHK-related (JP)
- Broadcast audio and branding belong to the respective rights holders

## Known Limitations

- Some API stations fail to play (expired URL, geo-block, broadcaster policy).
- **Nearby** sort only applies to stations with coordinates in Radio Browser.
- Korean/Japanese resolvers need maintenance when broadcaster APIs change.

## Related

- **Android**: [`../AuradioAndroid/README.md`](../AuradioAndroid/README.md)
