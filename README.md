# Auradio (iOS)

Asia and world radio streaming app for iPhone. Station metadata and stream URLs come from the [Radio Browser](https://www.radio-browser.info/) open API, with extra resolvers for major Korean and Japanese broadcasters.

Android port: sibling project [`AuradioAndroid`](../AuradioAndroid).

## Requirements

- Xcode 15 or later
- iOS 17.0 or later
- Physical iPhone recommended (background playback, Live Activity, location-based sort)

## Getting Started

1. Open `AsiaRadio.xcodeproj` in Xcode.
2. Select your Team under **Signing & Capabilities**.
3. Build and run on a device or simulator (⌘R).

If the debugger fails with `already being debugged`, stop the run, force-quit the app, quit Xcode, and run again. The shared scheme sets `IDEPreferLogStreaming=YES` to reduce logging timeouts.

## Features

### Tabs (5)

| Tab | Description |
|-----|-------------|
| **Channels** | All stations from 24 countries; sort by **Default** or **Nearby** |
| **Favorites** | Saved stations grouped by country |
| **Region** | Continent → country → station list |
| **Recent** | Last played stations (up to 20) |
| **Popular** | Top-voted stations per country |

### Channels tab

- Fetches up to **60 stations per country** from Radio Browser
- API order: `lastcheckok` (working streams first), then sorted by votes inside the app filter
- List order: continent → country
- **Default** — continent/country grouping from the API merge
- **Nearby** — sorts stations with `geo_lat` / `geo_long` by distance from current location (requires location permission; many stations have no coordinates)

### Playback

- Tap a row to play; mini player at the bottom, full player on tap
- Global search: name, frequency, tags, language, country
- **⋯ menu** on each row: Favorite, Startup Channel, Info
- Background audio, lock screen / Control Center metadata
- Live Activity widget (enable in Settings → Auradio → Live Activities)

### Settings (⚙️)

- **Sleep timer** — Duration or End Time; persists across relaunch until it fires
- **Startup channel** — optional auto-play on launch when enabled and a station is set
- App info and supported regions

## Supported Regions

**5 continents · 24 countries**

| Continent | Countries |
|-----------|-----------|
| Asia | 🇰🇷 Korea · 🇯🇵 Japan · 🇨🇳 China · 🇻🇳 Vietnam · 🇹🇭 Thailand · 🇵🇭 Philippines · 🇮🇩 Indonesia · 🇲🇾 Malaysia · 🇸🇬 Singapore · 🇮🇳 India · 🇹🇼 Taiwan · 🇭🇰 Hong Kong |
| Americas | 🇺🇸 United States · 🇨🇦 Canada |
| Europe | 🇫🇷 France · 🇩🇪 Germany · 🇪🇸 Spain · 🇷🇺 Russia |
| Oceania | 🇦🇺 Australia |
| Africa | 🇿🇦 South Africa · 🇪🇬 Egypt · 🇳🇬 Nigeria · 🇲🇦 Morocco · 🇰🇪 Kenya |

### Station filtering (API → app)

- `hidebroken=true` on API requests
- Drops OGG / VORBIS / OPUS codecs (iOS `AVPlayer` limitation)
- Keeps stations with `lastcheckok=1` **or** `votes ≥ 5`

## Project Structure

```
AsiaRadio/
├── AsiaRadio/
│   ├── AsiaRadioApp.swift              # App entry, prefetch
│   ├── AppDelegate.swift               # Background lifecycle
│   ├── ContentView.swift               # Banner, search, 5 tabs, sheets
│   ├── Models/
│   │   ├── AppInfo.swift
│   │   ├── AppSection.swift            # Tab definitions
│   │   ├── RadioStation.swift          # Station, country, continent, geo fields
│   │   └── RadioPlaybackAttributes.swift
│   ├── Services/
│   │   ├── AudioPlayerService.swift    # AVPlayer, queue, sleep timer, reconnect
│   │   ├── RadioBrowserAPI.swift       # API actor, cache, mirror failover
│   │   ├── KoreanStreamResolver.swift  # KBS / MBC / SBS live URLs
│   │   ├── JapaneseStreamResolver.swift
│   │   ├── StationArtworkResolver.swift
│   │   ├── StationFrequencyLookup.swift
│   │   ├── FavoritesStore.swift
│   │   ├── RecentStore.swift
│   │   ├── StartupChannelStore.swift
│   │   ├── LocationManager.swift       # Nearby sort
│   │   ├── ChannelSortMode.swift       # Default / Nearby sorting
│   │   ├── NowPlayingManager.swift
│   │   └── RadioLiveActivityManager.swift
│   └── Views/
│       ├── ChannelListView.swift
│       ├── RegionContentView.swift
│       ├── FavoritesContentView.swift
│       ├── RecentContentView.swift
│       ├── PopularContentView.swift
│       ├── AboutContentView.swift      # Settings
│       ├── StationRowView.swift
│       ├── StationInfoView.swift
│       ├── MiniPlayerView.swift
│       ├── PlayerView.swift
│       └── Components/
│           ├── MainHeaderBannerView.swift
│           ├── StationArtworkView.swift
│           └── SleepTimerIndicator.swift
├── AsiaRadioWidget/                    # Live Activity extension
└── scripts/generate_icons.swift
```

## Streams and Artwork

Radio Browser URLs can expire. Major broadcasters are refreshed at playback time:

| Broadcaster | Source |
|-------------|--------|
| KBS | `cfpwwwapi.kbs.co.kr` |
| MBC | `sminiplay.imbc.com` |
| SBS | `apis.sbs.co.kr` |
| NHK / JP stations | `JapaneseStreamResolver` |
| Others | Radio Browser URL + `radio.bsod.kr` proxy fallback |

Artwork resolution order: favicon → broadcaster logo → homepage Open Graph / touch icon → domain favicon.

## Build & Release

| Item | Value |
|------|-------|
| Product name | Auradio |
| Bundle ID | `com.jwoo.asiaradio` |
| Widget Bundle ID | `com.jwoo.asiaradio.widget` |
| Version | 1.0.0 |
| Min iOS | 17.0 |

```bash
# Command-line build
xcodebuild -scheme AsiaRadio -destination 'generic/platform=iOS' build
```

App Store: Archive in Xcode → upload to App Store Connect (Developer Program required).

## Regenerate Icons

```bash
swift scripts/generate_icons.swift AsiaRadio/Assets.xcassets/AppIcon.appiconset
```

## Data Sources

- [Radio Browser](https://www.radio-browser.info/) — station list, tags, geo, stream URLs
- Official broadcaster APIs — KBS / MBC / SBS (KR), NHK-related sources (JP)
- [radio.bsod.kr](https://radio.bsod.kr/) — stream proxy reference

## Known Limitations

- Some API stations fail to play (expired URL, geo-block, broadcaster policy).
- **Nearby** sort only applies to stations with coordinates in Radio Browser (often a small subset).
- Korean/Japanese resolvers need maintenance when broadcaster APIs change.
- Display name in Xcode build settings (`JK Radio`) may differ from `Info.plist` (`Auradio`) — align before release.

## Related

- **Android**: [`../AuradioAndroid/README.md`](../AuradioAndroid/README.md) — Jetpack Compose port with Google Play billing for premium sleep timer / startup channel.
