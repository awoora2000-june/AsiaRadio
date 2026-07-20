import Foundation

enum RadioBrowserError: LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingFailed
    case stationNotFound

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid request URL."
        case .invalidResponse: return "Could not load station list."
        case .decodingFailed: return "Could not decode station data."
        case .stationNotFound: return "Station not found."
        }
    }
}

actor RadioBrowserAPI {
    static let shared = RadioBrowserAPI()

    private let session: URLSession
    private let mirrors = [
        "https://de1.api.radio-browser.info/json",
        "https://nl1.api.radio-browser.info/json",
        "https://fi1.api.radio-browser.info/json"
    ]

    private var cache: [RadioCountry: [RadioStation]] = [:]
    private var popularCache: [RadioCountry: [RadioStation]] = [:]
    private var inflight: [RadioCountry: Task<[RadioStation], Error>] = [:]
    private var popularInflight: [RadioCountry: Task<[RadioStation], Error>] = [:]
    private var streamCache: [String: (station: RadioStation, fetchedAt: Date)] = [:]
    private var allStationsCache: [RadioStation]?
    private var allStationsInflight: Task<[RadioStation], Error>?

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = [
            "User-Agent": AppInfo.userAgent
        ]
        session = URLSession(configuration: config)
    }

    func cachedStations(for country: RadioCountry) -> [RadioStation]? {
        cache[country]
    }

    func resolvePrimaryKoreanURL(for station: RadioStation) async -> URL? {
        await KoreanStreamResolver.resolvePrimaryURL(for: station, session: session)
    }

    func resolvePrimaryJapaneseURL(for station: RadioStation) async -> URL? {
        await JapaneseStreamResolver.resolvePrimaryURL(for: station, session: session)
    }

    func playbackURLsForJapaneseStation(for station: RadioStation) async -> [URL] {
        await JapaneseStreamResolver.playbackURLs(for: station, session: session)
    }

    func warmKoreanBroadcasterCache(for stations: [RadioStation]) {
        guard !stations.isEmpty else { return }

        Task(priority: .utility) {
            for station in stations where KoreanStreamResolver.isMajorBroadcaster(station) {
                _ = await KoreanStreamResolver.resolvePrimaryURL(for: station, session: self.session)
            }
        }
    }

    func warmJapaneseBroadcasterCache(for stations: [RadioStation]) {
        guard !stations.isEmpty else { return }

        Task(priority: .utility) {
            for station in stations where JapaneseStreamResolver.isMajorBroadcaster(station) {
                _ = await JapaneseStreamResolver.resolvePrimaryURL(for: station, session: self.session)
            }
        }
    }

    func cachedPopularStations(for country: RadioCountry) -> [RadioStation]? {
        popularCache[country]
    }

    func fetchPopularStations(forceRefresh: Bool = false, limit: Int = 30) async throws -> [(country: RadioCountry, stations: [RadioStation])] {
        var groups: [(RadioCountry, [RadioStation])] = []

        for country in RadioCountry.allCases {
            let stations = try await fetchPopularStations(country: country, limit: limit, forceRefresh: forceRefresh)
            if !stations.isEmpty {
                groups.append((country, stations))
            }
        }

        return groups
    }

    func fetchPopularStations(country: RadioCountry, limit: Int = 30, forceRefresh: Bool = false) async throws -> [RadioStation] {
        if !forceRefresh, let cached = popularCache[country], !cached.isEmpty {
            return cached
        }

        if let inflight = popularInflight[country] {
            return try await inflight.value
        }

        let task = Task<[RadioStation], Error> {
            try await self.performPopularFetch(country: country, limit: limit)
        }

        popularInflight[country] = task
        defer { popularInflight[country] = nil }

        return try await task.value
    }

    func prefetch(countries: [RadioCountry] = RadioCountry.allCases) {
        Task(priority: .utility) {
            for country in countries {
                if self.cachedStations(for: country) != nil { continue }
                _ = try? await self.fetchStations(country: country)
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    func cachedAllStations() -> [RadioStation]? {
        if let allStationsCache, !allStationsCache.isEmpty {
            return allStationsCache
        }

        let merged = mergeCachedCountryStations()
        return merged.isEmpty ? nil : merged
    }

    func fetchAllStations(limitPerCountry: Int = 60, forceRefresh: Bool = false) async throws -> [RadioStation] {
        if !forceRefresh, let cached = cachedAllStations(), !cached.isEmpty, allStationsCache != nil {
            return cached
        }

        if let allStationsInflight {
            return try await allStationsInflight.value
        }

        let task = Task<[RadioStation], Error> {
            try await self.performFetchAll(limitPerCountry: limitPerCountry)
        }

        allStationsInflight = task
        defer { allStationsInflight = nil }

        return try await task.value
    }

    func fetchStations(country: RadioCountry, limit: Int = 60, forceRefresh: Bool = false) async throws -> [RadioStation] {
        if !forceRefresh, let cached = cache[country], !cached.isEmpty {
            return cached
        }

        if let inflight = inflight[country] {
            return try await inflight.value
        }

        let task = Task<[RadioStation], Error> {
            try await self.performFetch(country: country, limit: limit)
        }

        inflight[country] = task
        defer { inflight[country] = nil }

        return try await task.value
    }

    func stationByUUID(_ id: String) async throws -> RadioStation {
        if let cached = streamCache[id], Date().timeIntervalSince(cached.fetchedAt) < 120 {
            return cached.station
        }

        var lastError: Error = RadioBrowserError.stationNotFound

        for baseURL in mirrors {
            guard let url = URL(string: "\(baseURL)/stations/byuuid/\(id)") else { continue }

            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    continue
                }

                let stations = try JSONDecoder().decode([RadioStation].self, from: data)
                guard let station = stations.first else { continue }

                streamCache[id] = (station, Date())
                return station
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    func playableURLs(for station: RadioStation) async -> [URL] {
        var candidates: [URL] = station.playableURLs

        if station.countryCode.uppercased() == "KR" {
            candidates.append(contentsOf: await KoreanStreamResolver.resolveURLs(for: station, session: session))
        }

        if station.countryCode.uppercased() == "JP" {
            candidates.insert(
                contentsOf: await JapaneseStreamResolver.playbackURLs(for: station, session: session),
                at: 0
            )
        }

        if candidates.isEmpty {
            if let refreshed = try? await stationByUUID(station.id) {
                candidates.append(contentsOf: refreshed.playableURLs)
            }
        }

        var seen = Set<String>()
        return candidates.filter { url in
            let key = url.absoluteString
            guard key.hasPrefix("http"), seen.insert(key).inserted else { return false }
            return RadioStation.isLikelyStreamURL(url)
        }
    }

    private func performFetch(country: RadioCountry, limit: Int) async throws -> [RadioStation] {
        let stations = try await loadStationsFromNetwork(country: country, limit: limit, order: "lastcheckok")
        cache[country] = stations
        allStationsCache = nil
        if country == .korea {
            warmKoreanBroadcasterCache(for: Array(stations.prefix(20)))
        }
        if country == .japan {
            warmJapaneseBroadcasterCache(for: Array(stations.prefix(20)))
        }
        return stations
    }

    private func performFetchAll(limitPerCountry: Int) async throws -> [RadioStation] {
        try await withThrowingTaskGroup(of: (RadioCountry, [RadioStation]).self) { group in
            for country in RadioCountry.allCases {
                group.addTask {
                    let stations = try await self.fetchStations(country: country, limit: limitPerCountry)
                    return (country, stations)
                }
            }

            var grouped: [(RadioCountry, [RadioStation])] = []
            for try await result in group {
                grouped.append(result)
            }

            let stations = sortAllStations(grouped)
            allStationsCache = stations
            return stations
        }
    }

    private func mergeCachedCountryStations() -> [RadioStation] {
        let grouped = RadioCountry.allCases.compactMap { country -> (RadioCountry, [RadioStation])? in
            guard let stations = cache[country], !stations.isEmpty else { return nil }
            return (country, stations)
        }
        return sortAllStations(grouped)
    }

    private func sortAllStations(_ grouped: [(RadioCountry, [RadioStation])]) -> [RadioStation] {
        let continentOrder = RadioContinent.allCases
        return grouped
            .sorted {
                let lhs = continentOrder.firstIndex(of: $0.0.continent) ?? 0
                let rhs = continentOrder.firstIndex(of: $1.0.continent) ?? 0
                if lhs != rhs { return lhs < rhs }
                return $0.0.title < $1.0.title
            }
            .flatMap(\.1)
    }

    private func performPopularFetch(country: RadioCountry, limit: Int) async throws -> [RadioStation] {
        let stations = try await loadStationsFromNetwork(country: country, limit: limit, order: "votes")
        popularCache[country] = stations
        return stations
    }

    private func loadStationsFromNetwork(country: RadioCountry, limit: Int, order: String) async throws -> [RadioStation] {
        var lastError: Error = RadioBrowserError.invalidResponse

        for baseURL in mirrors {
            var components = URLComponents(string: "\(baseURL)/stations/search")
            components?.queryItems = [
                URLQueryItem(name: "countrycode", value: country.rawValue),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "order", value: order),
                URLQueryItem(name: "reverse", value: "true"),
                URLQueryItem(name: "hidebroken", value: "true")
            ]

            guard let url = components?.url else {
                lastError = RadioBrowserError.invalidURL
                continue
            }

            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    continue
                }

                let stations = try JSONDecoder().decode([RadioStation].self, from: data)
                return sanitize(stations)
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private func sanitize(_ stations: [RadioStation]) -> [RadioStation] {
        stations
            .filter { $0.isSupportedCodec }
            .filter { $0.hasLikelyPlayableStreamURL }
            .filter { $0.lastCheckOK || $0.votes >= 5 }
            .sorted {
                if $0.lastCheckOK != $1.lastCheckOK {
                    return $0.lastCheckOK && !$1.lastCheckOK
                }
                return $0.votes > $1.votes
            }
    }
}
