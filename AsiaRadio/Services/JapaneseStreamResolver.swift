import Foundation

enum JapaneseStreamResolver {
    private struct NHKTarget {
        let area: String
        let channel: String
    }

    private static var nhkStreamsCache: (fetchedAt: Date, streams: [String: [String: URL]])?
    private static var stationCache: [String: (urls: [URL], fetchedAt: Date)] = [:]
    private static let cacheTTL: TimeInterval = 300
    private static let nhkConfigTTL: TimeInterval = 3600

    static func isNHKStation(_ station: RadioStation) -> Bool {
        guard station.countryCode.uppercased() == "JP" else { return false }
        let name = normalized(station.name)
        return name.contains("nhk") && !name.contains("world")
    }

    static func isMajorBroadcaster(_ station: RadioStation) -> Bool {
        isNHKStation(station)
    }

    static func playbackURLs(for station: RadioStation, session: URLSession) async -> [URL] {
        guard station.countryCode.uppercased() == "JP", isNHKStation(station) else { return [] }

        if let cached = stationCache[station.id],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.urls
        }

        var urls = instantPlaybackURLs(for: station)

        if let target = nhkTarget(for: station),
           let official = await resolveNHK(target: target, session: session) {
            urls.append(official)
        }

        let resolved = deduplicated(urls)
        if !resolved.isEmpty {
            stationCache[station.id] = (resolved, Date())
        }
        return resolved
    }

    static func instantPlaybackURLs(for station: RadioStation) -> [URL] {
        guard let target = nhkTarget(for: station) else { return [] }

        let mirrors: [String]
        switch target.channel {
        case "fmhls":
            mirrors = [
                "http://mnet.x10.mx/nhkfm.m3u8",
                "http://mnet.x10.mx/nhkr.php?id=5"
            ]
        case "r2hls":
            mirrors = [
                "http://mnet.x10.mx/nhkr.php?id=4"
            ]
        default:
            mirrors = [
                "http://mnet.x10.mx/nhkr.php?id=3"
            ]
        }

        return mirrors.compactMap { URL(string: $0) }
    }

    static func resolvePrimaryURL(for station: RadioStation, session: URLSession) async -> URL? {
        await playbackURLs(for: station, session: session).first
    }

    static func resolveURLs(for station: RadioStation, session: URLSession) async -> [URL] {
        await playbackURLs(for: station, session: session)
    }

    private static func resolveNHK(target: NHKTarget, session: URLSession) async -> URL? {
        guard let streams = await loadNHKStreams(session: session),
              let channelURLs = streams[target.area],
              let url = channelURLs[target.channel] else {
            return nil
        }
        return url
    }

    private static func loadNHKStreams(session: URLSession) async -> [String: [String: URL]]? {
        if let cached = nhkStreamsCache,
           Date().timeIntervalSince(cached.fetchedAt) < nhkConfigTTL {
            return cached.streams
        }

        guard let apiURL = URL(string: "https://www.nhk.or.jp/radio/config/config_web.xml") else {
            return nhkStreamsCache?.streams
        }

        do {
            let (data, response) = try await session.data(from: apiURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let xml = String(data: data, encoding: .utf8) else {
                return nhkStreamsCache?.streams
            }

            let streams = parseNHKConfig(xml)
            guard !streams.isEmpty else { return nhkStreamsCache?.streams }

            nhkStreamsCache = (Date(), streams)
            return streams
        } catch {
            return nhkStreamsCache?.streams
        }
    }

    private static func parseNHKConfig(_ xml: String) -> [String: [String: URL]] {
        var result: [String: [String: URL]] = [:]
        let nsXML = xml as NSString
        let blockRegex = try? NSRegularExpression(pattern: "<data>(.*?)</data>", options: [.dotMatchesLineSeparators])
        let matches = blockRegex?.matches(in: xml, range: NSRange(location: 0, length: nsXML.length)) ?? []

        for match in matches where match.numberOfRanges > 1 {
            let block = nsXML.substring(with: match.range(at: 1))
            guard let area = capture(in: block, pattern: "<area>([^<]+)</area>"),
                  let r1 = cdata(in: block, tag: "r1hls"), let r1URL = URL(string: r1),
                  let r2 = cdata(in: block, tag: "r2hls"), let r2URL = URL(string: r2),
                  let fm = cdata(in: block, tag: "fmhls"), let fmURL = URL(string: fm) else {
                continue
            }

            result[area] = [
                "r1hls": r1URL,
                "r2hls": r2URL,
                "fmhls": fmURL
            ]
        }

        return result
    }

    private static func nhkTarget(for station: RadioStation) -> NHKTarget? {
        guard isNHKStation(station) else { return nil }

        let name = normalized(station.name)
        let channel: String
        if matches(name, any: ["nhk-fm", "nhk fm", "nhkfm"]) {
            channel = "fmhls"
        } else if matches(name, any: ["r2", "radio 2", "ラジオ2", "nhk-r2", "nhkr2"]) {
            channel = "r2hls"
        } else if matches(name, any: ["culture", "文体"]) {
            channel = "fmhls"
        } else if matches(name, any: ["r1", "radio 1", "ラジオ1", "nhk-r1", "nhkr1"]) {
            channel = "r1hls"
        } else if matches(name, any: [" fm", "fm "]) || name.hasSuffix("fm") {
            channel = "fmhls"
        } else {
            channel = "r1hls"
        }

        let area = parseArea(from: name) ?? "tokyo"
        return NHKTarget(area: area, channel: channel)
    }

    private static func parseArea(from name: String) -> String? {
        let areas: [(String, [String])] = [
            ("sapporo", ["sapporo", "札幌"]),
            ("sendai", ["sendai", "仙台"]),
            ("tokyo", ["tokyo", "東京"]),
            ("nagoya", ["nagoya", "名古屋"]),
            ("osaka", ["osaka", "大阪"]),
            ("hiroshima", ["hiroshima", "広島"]),
            ("matsuyama", ["matsuyama", "松山"]),
            ("fukuoka", ["fukuoka", "福岡"])
        ]

        for (area, keywords) in areas where matches(name, any: keywords) {
            return area
        }
        return nil
    }

    private static func capture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func cdata(in text: String, tag: String) -> String? {
        capture(in: text, pattern: "<\(tag)><!\\[CDATA\\[([^\\]]+)\\]\\]></\(tag)>")
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private static func matches(_ haystack: String, any needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            let key = url.absoluteString
            guard key.hasPrefix("http"), seen.insert(key).inserted else { return false }
            return true
        }
    }
}
