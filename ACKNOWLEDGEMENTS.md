# Acknowledgements

Auradio includes original work by Jwoo and relies on the following third-party
services and data. This file is the source of truth for App Store / Play
attribution and in-app “Legal & Acknowledgements” copy.

## Data and streaming

| Source | Role | Notes |
|--------|------|--------|
| [Radio Browser](https://www.radio-browser.info/) | Station metadata and stream URLs | Community project. Clients should identify via User-Agent (`Auradio/1.0`). Station data and streams remain the responsibility of each broadcaster. |
| KBS / MBC / SBS (Korea) | Live stream resolution | Public station APIs / endpoints used only to obtain playable stream URLs for registered stations. |
| NHK and related JP sources | Live stream resolution | Used to refresh playable URLs when Radio Browser links are stale. |
| [radio.bsod.jp](https://radio.bsod.jp/) | Optional stream proxy fallback | Third-party proxy; used only as a playback fallback. |
| Station favicons / logos | Artwork | Loaded from station sites, Radio Browser favicon fields, or public favicon services at runtime. Not redistributed as owned assets. |

Broadcast content (audio, logos, station names, trademarks) belongs to the
respective rights holders. Auradio does not claim ownership of broadcast
programming. Availability may vary by region and broadcaster policy.

## Apple / Google platforms

| Component | Role |
|-----------|------|
| Apple SDKs (AVFoundation, StoreKit, CoreLocation, UserNotifications, SwiftUI, …) | System frameworks under Apple’s terms |
| Google Play Billing / AndroidX / Media3 (Android port) | See `AuradioAndroid` dependency licenses |

## App assets (original)

| Asset | Ownership |
|-------|-----------|
| App icon (`AppIcon`) | Original artwork generated for Auradio (Jwoo) |
| Main header banner | Original artwork for Auradio (Jwoo) |
| UI copy and layout | Original (Jwoo) |

No third-party commercial fonts are bundled; system fonts are used.

## Contact

Copyright questions: support@jwoo.dev
