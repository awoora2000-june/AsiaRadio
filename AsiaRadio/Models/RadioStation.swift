import Foundation

struct RadioStation: Identifiable, Hashable {
    let id: String
    let name: String
    let streamURL: URL
    let backupStreamURL: URL?
    let homepage: String?
    let favicon: String?
    let countryCode: String
    let country: String
    let language: String?
    let tags: String?
    let codec: String?
    let bitrate: Int?
    let votes: Int
    let lastCheckOK: Bool
    let isHLS: Bool
    let geoLat: Double?
    let geoLong: Double?

    init(
        id: String,
        name: String,
        streamURL: URL,
        backupStreamURL: URL? = nil,
        homepage: String? = nil,
        favicon: String? = nil,
        countryCode: String,
        country: String,
        language: String? = nil,
        tags: String? = nil,
        codec: String? = nil,
        bitrate: Int? = nil,
        votes: Int = 0,
        lastCheckOK: Bool = true,
        isHLS: Bool = false,
        geoLat: Double? = nil,
        geoLong: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.backupStreamURL = backupStreamURL
        self.homepage = homepage
        self.favicon = favicon
        self.countryCode = countryCode
        self.country = country
        self.language = language
        self.tags = tags
        self.codec = codec
        self.bitrate = bitrate
        self.votes = votes
        self.lastCheckOK = lastCheckOK
        self.isHLS = isHLS
        self.geoLat = geoLat
        self.geoLong = geoLong
    }

    var displayCountry: String {
        RadioCountry(countryCode: countryCode)?.title ?? country
    }

    var flagEmoji: String {
        RadioCountry(countryCode: countryCode)?.flag ?? "📻"
    }

    var displayFrequency: String {
        StationFrequencyLookup.resolve(for: self) ?? "—"
    }

    var hasFrequency: Bool {
        displayFrequency != "—"
    }

    var isSupportedCodec: Bool {
        guard let codec else { return true }
        let normalized = codec.uppercased()
        if normalized.isEmpty || normalized == "UNKNOWN" { return true }
        if normalized.contains("OGG") || normalized.contains("VORBIS") || normalized.contains("OPUS") {
            return false
        }
        return true
    }

    var playableURLs: [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        for url in [streamURL, backupStreamURL].compactMap({ $0 }) {
            let key = url.absoluteString
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            guard Self.isLikelyStreamURL(url) else { continue }
            urls.append(url)
        }
        return urls
    }

    var hasLikelyPlayableStreamURL: Bool {
        !playableURLs.isEmpty
    }

    static func isLikelyStreamURL(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()

        let streamMarkers = [
            ".m3u8", ".mp3", ".aac", ".pls", ".asx",
            "/stream", "/radio", "/live", "/listen", "/hls",
            "icecast", "shoutcast", "/proxy", "/play", "playlist"
        ]
        if streamMarkers.contains(where: { lower.contains($0) }) {
            return true
        }

        if let port = url.port, port != 80, port != 443 {
            return true
        }

        if lower.contains(":8") {
            return true
        }

        let path = url.path.lowercased()
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.isEmpty {
            return url.query != nil
        }

        if path.hasSuffix(".html") || path.hasSuffix(".htm") {
            return false
        }

        if path.hasSuffix(".php"), !lower.contains("nhkr.php") {
            return false
        }

        return true
    }

    var prioritizedPlayableURLs: [URL] {
        if isHLS {
            return playableURLs.sorted { hlsPriority(for: $0) < hlsPriority(for: $1) }
        }
        return playableURLs.sorted { connectionPriority(for: $0) < connectionPriority(for: $1) }
    }

    private func hlsPriority(for url: URL) -> Int {
        let value = url.absoluteString.lowercased()
        if value.contains(".m3u8") || value.contains("/hls") {
            return 0
        }
        return connectionPriority(for: url)
    }

    private func connectionPriority(for url: URL) -> Int {
        let value = url.absoluteString.lowercased()
        if value.contains(".m3u8") || value.contains("/hls") || value.contains("playlist.m3u8") {
            return 30
        }
        if value.contains("bsod.kr") {
            return 25
        }
        if value.contains(".mp3") || value.contains(".aac") || value.contains("/aac") {
            return 0
        }
        if value.contains("icecast") || value.contains(":8") {
            return 5
        }
        return 15
    }
}

extension RadioStation: Codable {
    enum CodingKeys: String, CodingKey {
        case id = "stationuuid"
        case name
        case urlResolved = "url_resolved"
        case url
        case homepage
        case favicon
        case countryCode = "countrycode"
        case country
        case language
        case tags
        case codec
        case bitrate
        case votes
        case lastcheckok
        case hls
        case geoLat = "geo_lat"
        case geoLong = "geo_long"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        homepage = try container.decodeIfPresent(String.self, forKey: .homepage)
        favicon = try container.decodeIfPresent(String.self, forKey: .favicon)
        countryCode = try container.decode(String.self, forKey: .countryCode)
        country = try container.decode(String.self, forKey: .country)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        tags = try container.decodeIfPresent(String.self, forKey: .tags)
        codec = try container.decodeIfPresent(String.self, forKey: .codec)
        bitrate = try container.decodeIfPresent(Int.self, forKey: .bitrate)
        votes = try container.decodeIfPresent(Int.self, forKey: .votes) ?? 0
        lastCheckOK = (try container.decodeIfPresent(Int.self, forKey: .lastcheckok) ?? 0) == 1
        isHLS = (try container.decodeIfPresent(Int.self, forKey: .hls) ?? 0) == 1
        geoLat = try container.decodeIfPresent(Double.self, forKey: .geoLat)
        geoLong = try container.decodeIfPresent(Double.self, forKey: .geoLong)

        let resolved = try container.decodeIfPresent(String.self, forKey: .urlResolved)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let original = try container.decodeIfPresent(String.self, forKey: .url)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let primaryString = !resolved.isEmpty ? resolved : original
        guard let primaryURL = URL(string: primaryString), !primaryString.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .urlResolved,
                in: container,
                debugDescription: "Missing playable stream URL"
            )
        }

        streamURL = primaryURL

        if !original.isEmpty, original != primaryString, let backup = URL(string: original) {
            backupStreamURL = backup
        } else if !resolved.isEmpty, resolved != original, let backup = URL(string: resolved) {
            backupStreamURL = backup
        } else {
            backupStreamURL = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(streamURL.absoluteString, forKey: .urlResolved)
        try container.encodeIfPresent(backupStreamURL?.absoluteString, forKey: .url)
        try container.encodeIfPresent(homepage, forKey: .homepage)
        try container.encodeIfPresent(favicon, forKey: .favicon)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encode(country, forKey: .country)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(codec, forKey: .codec)
        try container.encodeIfPresent(bitrate, forKey: .bitrate)
        try container.encode(votes, forKey: .votes)
        try container.encode(lastCheckOK ? 1 : 0, forKey: .lastcheckok)
        try container.encode(isHLS ? 1 : 0, forKey: .hls)
        try container.encodeIfPresent(geoLat, forKey: .geoLat)
        try container.encodeIfPresent(geoLong, forKey: .geoLong)
    }
}

enum RadioCountry: String, CaseIterable, Identifiable {
    case korea = "KR"
    case japan = "JP"
    case china = "CN"
    case hongKong = "HK"
    case vietnam = "VN"
    case thailand = "TH"
    case philippines = "PH"
    case indonesia = "ID"
    case malaysia = "MY"
    case singapore = "SG"
    case india = "IN"
    case taiwan = "TW"
    case usa = "US"
    case canada = "CA"
    case france = "FR"
    case australia = "AU"
    case germany = "DE"
    case russia = "RU"
    case spain = "ES"
    case southAfrica = "ZA"
    case egypt = "EG"
    case nigeria = "NG"
    case morocco = "MA"
    case kenya = "KE"

    static let internationalCases: [RadioCountry] = allCases.filter { $0.continent != .asia }

    static let channelCases: [RadioCountry] = allCases

    var continent: RadioContinent {
        switch self {
        case .korea, .japan, .china, .vietnam, .thailand, .philippines,
             .indonesia, .malaysia, .singapore, .india, .taiwan, .hongKong:
            return .asia
        case .france, .germany, .spain, .russia:
            return .europe
        case .usa, .canada:
            return .america
        case .southAfrica, .egypt, .nigeria, .morocco, .kenya:
            return .africa
        case .australia:
            return .oceania
        }
    }

    var id: String { rawValue }

    init?(countryCode: String) {
        self.init(rawValue: countryCode.uppercased())
    }

    var title: String {
        switch self {
        case .korea: return "Korea"
        case .japan: return "Japan"
        case .china: return "China"
        case .vietnam: return "Vietnam"
        case .thailand: return "Thailand"
        case .philippines: return "Philippines"
        case .indonesia: return "Indonesia"
        case .malaysia: return "Malaysia"
        case .singapore: return "Singapore"
        case .india: return "India"
        case .taiwan: return "Taiwan"
        case .hongKong: return "Hong Kong"
        case .usa: return "United States"
        case .canada: return "Canada"
        case .france: return "France"
        case .australia: return "Australia"
        case .germany: return "Germany"
        case .russia: return "Russia"
        case .spain: return "Spain"
        case .southAfrica: return "South Africa"
        case .egypt: return "Egypt"
        case .nigeria: return "Nigeria"
        case .morocco: return "Morocco"
        case .kenya: return "Kenya"
        }
    }

    var flag: String {
        switch self {
        case .korea: return "🇰🇷"
        case .japan: return "🇯🇵"
        case .china: return "🇨🇳"
        case .vietnam: return "🇻🇳"
        case .thailand: return "🇹🇭"
        case .philippines: return "🇵🇭"
        case .indonesia: return "🇮🇩"
        case .malaysia: return "🇲🇾"
        case .singapore: return "🇸🇬"
        case .india: return "🇮🇳"
        case .taiwan: return "🇹🇼"
        case .hongKong: return "🇭🇰"
        case .usa: return "🇺🇸"
        case .canada: return "🇨🇦"
        case .france: return "🇫🇷"
        case .australia: return "🇦🇺"
        case .germany: return "🇩🇪"
        case .russia: return "🇷🇺"
        case .spain: return "🇪🇸"
        case .southAfrica: return "🇿🇦"
        case .egypt: return "🇪🇬"
        case .nigeria: return "🇳🇬"
        case .morocco: return "🇲🇦"
        case .kenya: return "🇰🇪"
        }
    }

    /// Approximate capital / center coordinates for proximity sorting.
    var approximateCoordinate: (latitude: Double, longitude: Double) {
        switch self {
        case .korea: return (37.5665, 126.9780)
        case .japan: return (35.6762, 139.6503)
        case .china: return (39.9042, 116.4074)
        case .hongKong: return (22.3193, 114.1694)
        case .vietnam: return (21.0285, 105.8542)
        case .thailand: return (13.7563, 100.5018)
        case .philippines: return (14.5995, 120.9842)
        case .indonesia: return (-6.2088, 106.8456)
        case .malaysia: return (3.1390, 101.6869)
        case .singapore: return (1.3521, 103.8198)
        case .india: return (28.6139, 77.2090)
        case .taiwan: return (25.0330, 121.5654)
        case .usa: return (38.9072, -77.0369)
        case .canada: return (45.4215, -75.6972)
        case .france: return (48.8566, 2.3522)
        case .australia: return (-35.2809, 149.1300)
        case .germany: return (52.5200, 13.4050)
        case .russia: return (55.7558, 37.6173)
        case .spain: return (40.4168, -3.7038)
        case .southAfrica: return (-25.7479, 28.2293)
        case .egypt: return (30.0444, 31.2357)
        case .nigeria: return (9.0765, 7.3986)
        case .morocco: return (33.9716, -6.8498)
        case .kenya: return (-1.2921, 36.8219)
        }
    }
}

enum RadioContinent: String, CaseIterable, Identifiable {
    case asia
    case america
    case europe
    case oceania
    case africa

    var id: String { rawValue }

    var title: String {
        switch self {
        case .asia: return "Asia"
        case .europe: return "Europe"
        case .america: return "Americas"
        case .africa: return "Africa"
        case .oceania: return "Oceania"
        }
    }

    var icon: String {
        switch self {
        case .asia: return "🏯"
        case .europe: return "🏰"
        case .america: return "🗽"
        case .africa: return "🦁"
        case .oceania: return "🏝️"
        }
    }

    var countries: [RadioCountry] {
        RadioCountry.allCases.filter { $0.continent == self }
    }
}
