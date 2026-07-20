import Foundation

enum KoreanStreamResolver {
    private static var cache: [String: (urls: [URL], fetchedAt: Date)] = [:]
    private static let cacheTTL: TimeInterval = 300

    private struct KBSResponse: Decodable {
        struct ChannelItem: Decodable {
            let serviceURL: String

            enum CodingKeys: String, CodingKey {
                case serviceURL = "service_url"
            }
        }

        let channelItem: [ChannelItem]?

        enum CodingKeys: String, CodingKey {
            case channelItem = "channel_item"
        }
    }

    static func instantURLs(for station: RadioStation) -> [URL] {
        guard station.countryCode.uppercased() == "KR" else { return [] }
        if let url = proxyURL(for: station) {
            return [url]
        }
        return []
    }

    static func isMajorBroadcaster(_ station: RadioStation) -> Bool {
        guard station.countryCode.uppercased() == "KR" else { return false }
        return kbsChannelCode(for: station) != nil
            || mbcChannelCode(for: station) != nil
            || sbsEndpoint(for: station) != nil
    }

    static func resolvePrimaryURL(for station: RadioStation, session: URLSession) async -> URL? {
        guard station.countryCode.uppercased() == "KR" else { return nil }

        if let cached = cache[station.id],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL,
           let preferred = cached.urls.first(where: { !isProxyURL($0) }) ?? cached.urls.first {
            return preferred
        }

        guard let primary = await fetchPrimaryURL(for: station, session: session) else {
            return nil
        }

        var urls = [primary]
        urls.append(contentsOf: instantURLs(for: station))
        cache[station.id] = (deduplicated(urls), Date())
        return primary
    }

    static func resolveURLs(for station: RadioStation, session: URLSession) async -> [URL] {
        guard station.countryCode.uppercased() == "KR" else { return [] }

        if let cached = cache[station.id],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.urls
        }

        var urls: [URL] = []
        if let primary = await fetchPrimaryURL(for: station, session: session) {
            urls.append(primary)
        }
        urls.append(contentsOf: instantURLs(for: station))

        let resolved = deduplicated(urls)
        if !resolved.isEmpty {
            cache[station.id] = (resolved, Date())
        }
        return resolved
    }

    private static func fetchPrimaryURL(for station: RadioStation, session: URLSession) async -> URL? {
        if kbsChannelCode(for: station) != nil {
            return await resolveKBS(for: station, session: session)
        }
        if mbcChannelCode(for: station) != nil {
            return await resolveMBC(for: station, session: session)
        }
        if sbsEndpoint(for: station) != nil {
            return await resolveSBS(for: station, session: session)
        }
        return nil
    }

    private static func isProxyURL(_ url: URL) -> Bool {
        url.host?.contains("bsod.kr") == true
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            let key = url.absoluteString
            guard key.hasPrefix("http"), seen.insert(key).inserted else { return false }
            return true
        }
    }

    private static func resolveKBS(for station: RadioStation, session: URLSession) async -> URL? {
        guard let code = kbsChannelCode(for: station) else { return nil }
        guard let apiURL = URL(string: "https://cfpwwwapi.kbs.co.kr/api/v1/landing/live/channel_code/\(code)") else {
            return nil
        }

        do {
            let (data, response) = try await session.data(from: apiURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }

            let payload = try JSONDecoder().decode(KBSResponse.self, from: data)
            guard let raw = payload.channelItem?.first?.serviceURL.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: raw), !raw.isEmpty else {
                return nil
            }
            return url
        } catch {
            return nil
        }
    }

    private static func resolveMBC(for station: RadioStation, session: URLSession) async -> URL? {
        guard let channel = mbcChannelCode(for: station) else { return nil }
        guard let apiURL = URL(string: "https://sminiplay.imbc.com/aacplay.ashx?agent=webapp&channel=\(channel)") else {
            return nil
        }

        do {
            let (data, response) = try await session.data(from: apiURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }

            guard let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: raw), raw.hasPrefix("http") else {
                return nil
            }
            return url
        } catch {
            return nil
        }
    }

    private static func resolveSBS(for station: RadioStation, session: URLSession) async -> URL? {
        guard let endpoint = sbsEndpoint(for: station) else { return nil }
        guard let apiURL = URL(
            string: "https://apis.sbs.co.kr/play-api/1.0/livestream/\(endpoint.path)/\(endpoint.channel)?protocol=hls&ssl=Y"
        ) else {
            return nil
        }

        do {
            let (data, response) = try await session.data(from: apiURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }

            guard let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: raw), raw.hasPrefix("http") else {
                return nil
            }
            return url
        } catch {
            return nil
        }
    }

    private static func kbsChannelCode(for station: RadioStation) -> String? {
        let name = normalized(station.name)
        let hosts = station.playableURLs.compactMap { $0.host?.lowercased() }

        if hosts.contains(where: { $0.contains("gscdn.kbs.co.kr") }) {
            for url in station.playableURLs {
                let path = url.path.lowercased()
                if path.contains("1radio") { return "21" }
                if path.contains("2radio") { return "22" }
                if path.contains("3radio") { return "23" }
                if path.contains("1fm") { return "24" }
                if path.contains("2fm") { return "25" }
                if path.contains("hanminjok") { return "26" }
            }
        }

        guard name.contains("kbs") || name.contains("한국방송") else { return nil }

        if matches(name, any: ["1radio", "1r", "1라디오", "1 radio"]) { return "21" }
        if matches(name, any: ["2radio", "2r", "2라디오", "happy", "해피"]) { return "22" }
        if matches(name, any: ["3radio", "3r", "3라디오"]) { return "23" }
        if matches(name, any: ["classic", "1fm", "클래식", "음악fm"]) { return "24" }
        if matches(name, any: ["cool", "2fm", "쿨"]) { return "25" }
        if matches(name, any: ["hanminjok", "한민족"]) { return "26" }

        return nil
    }

    private static func mbcChannelCode(for station: RadioStation) -> String? {
        let name = normalized(station.name)
        let hosts = station.playableURLs.compactMap { $0.host?.lowercased() }

        if hosts.contains(where: { $0.contains("imbc.com") }) {
            for url in station.playableURLs {
                let absolute = url.absoluteString.lowercased()
                if absolute.contains("mfm") || absolute.contains("fm4u") { return "mfm" }
                if absolute.contains("sfm") || absolute.contains("fullmfm") { return "sfm" }
            }
        }

        guard name.contains("mbc") else { return nil }

        if matches(name, any: ["fm4u", "fm for you", "mfm", "mini"]) && !name.contains("표준") {
            return "mfm"
        }
        if matches(name, any: ["표준", "standard", "sfm", "for you"]) {
            return "sfm"
        }
        if name.contains("올댓") || name.contains("all that") {
            return "chm"
        }

        return nil
    }

    private static func sbsEndpoint(for station: RadioStation) -> (path: String, channel: String)? {
        let name = normalized(station.name)
        let hosts = station.playableURLs.compactMap { $0.host?.lowercased() }

        if hosts.contains(where: { $0.contains("sbs.co.kr") }) {
            for url in station.playableURLs {
                let absolute = url.absoluteString.lowercased()
                if absolute.contains("love") { return ("lovepc", "lovefm") }
                if absolute.contains("power") { return ("powerpc", "powerfm") }
                if absolute.contains("dmb") || absolute.contains("gorilla") { return ("sbsdmbpc", "sbsdmb") }
            }
        }

        guard name.contains("sbs") else { return nil }

        if matches(name, any: ["love", "러브"]) { return ("lovepc", "lovefm") }
        if matches(name, any: ["power", "파워"]) { return ("powerpc", "powerfm") }
        if matches(name, any: ["gorilla", "고릴라", "dmb"]) { return ("sbsdmbpc", "sbsdmb") }

        return nil
    }

    private static func proxyURL(for station: RadioStation) -> URL? {
        let name = normalized(station.name)

        if name.contains("kbs") || station.playableURLs.contains(where: { $0.host?.contains("gscdn.kbs.co.kr") == true }) {
            if let ch = kbsProxyChannel(for: station) {
                return URL(string: "https://radio.bsod.kr/stream/?stn=kbs&ch=\(ch)")
            }
        }

        if name.contains("mbc") || station.playableURLs.contains(where: { $0.host?.contains("imbc.com") == true }) {
            if let ch = mbcProxyChannel(for: station) {
                return URL(string: "https://radio.bsod.kr/stream/?stn=mbc&ch=\(ch)")
            }
        }

        if name.contains("sbs") || station.playableURLs.contains(where: { $0.host?.contains("sbs.co.kr") == true }) {
            if let ch = sbsProxyChannel(for: station) {
                return URL(string: "https://radio.bsod.kr/stream/?stn=sbs&ch=\(ch)")
            }
        }

        return nil
    }

    private static func kbsProxyChannel(for station: RadioStation) -> String? {
        switch kbsChannelCode(for: station) {
        case "21": return "1radio"
        case "22": return "2radio"
        case "23": return "3radio"
        case "24": return "1fm"
        case "25": return "2fm"
        case "26": return "hanminjok"
        default: return nil
        }
    }

    private static func mbcProxyChannel(for station: RadioStation) -> String? {
        switch mbcChannelCode(for: station) {
        case "sfm": return "sfm"
        case "mfm": return "fm4u"
        case "chm": return "chm"
        default: return nil
        }
    }

    private static func sbsProxyChannel(for station: RadioStation) -> String? {
        guard let endpoint = sbsEndpoint(for: station) else { return nil }
        switch endpoint.channel {
        case "lovefm": return "lovefm"
        case "powerfm": return "powerfm"
        case "sbsdmb": return "dmb"
        default: return nil
        }
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private static func matches(_ haystack: String, any needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
