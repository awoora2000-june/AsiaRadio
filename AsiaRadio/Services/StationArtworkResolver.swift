import Foundation
import UIKit

actor StationArtworkResolver {
    static let shared = StationArtworkResolver()

    private let session: URLSession
    private var stationCache: [String: [URL]] = [:]
    private var homepageCache: [String: [URL]] = [:]
    private var inflight: [String: Task<[URL], Never>] = [:]

    private static let curatedByHost: [String: String] = [
        "www.kbs.co.kr": "https://res.static.kbs.co.kr/favicon.png",
        "kbs.co.kr": "https://res.static.kbs.co.kr/favicon.png",
        "www.imbc.com": "https://img.imbc.com/commons/2018/image/comm2018noti/meta_mbc.png",
        "imbc.com": "https://img.imbc.com/commons/2018/image/comm2018noti/meta_mbc.png",
        "m.imbc.com": "https://img.imbc.com/commons/2018/image/comm2018noti/meta_mbc.png",
        "miniplay.imbc.com": "https://img.imbc.com/commons/2018/image/comm2018noti/meta_mbc.png",
        "www.sbs.co.kr": "https://program-image.cloud.sbs.co.kr/og/2025/sbs_home.png",
        "sbs.co.kr": "https://program-image.cloud.sbs.co.kr/og/2025/sbs_home.png",
        "www.cbs.co.kr": "https://www.cbs.co.kr/img/og_image.png",
        "cbs.co.kr": "https://www.cbs.co.kr/img/og_image.png",
        "m-aac.cbs.co.kr": "https://www.cbs.co.kr/img/og_image.png",
        "www.arirang.com": "https://www.arirang.com/images/logo192.png",
        "arirang.com": "https://www.arirang.com/images/logo192.png",
        "www.arirang.co.kr": "https://www.arirang.com/images/logo192.png",
        "ebsonair.ebs.co.kr": "https://www.ebs.co.kr/images/favicon.ico",
        "ebsonairios.ebs.co.kr": "https://www.ebs.co.kr/images/favicon.ico",
        "www.ebs.co.kr": "https://www.ebs.co.kr/images/favicon.ico",
        "ebs.co.kr": "https://www.ebs.co.kr/images/favicon.ico",
        "cdnfm.tbs.seoul.kr": "https://www.tbs.seoul.kr/favicon.ico",
        "www.tbs.seoul.kr": "https://www.tbs.seoul.kr/favicon.ico",
        "tbs.seoul.kr": "https://www.tbs.seoul.kr/favicon.ico",
        "mgugaklive.nowcdn.co.kr": "https://www.google.com/s2/favicons?domain=mgugaklive.nowcdn.co.kr&sz=128",
        "radiolive.ytn.co.kr": "https://www.ytn.co.kr/favicon.ico",
        "www.ytn.co.kr": "https://www.ytn.co.kr/favicon.ico",
        "radio2.tbn.or.kr": "https://www.tbn.or.kr/favicon.ico",
        "www.tbn.or.kr": "https://www.tbn.or.kr/favicon.ico",
        "bbslive.clouducs.com": "https://bbslive.clouducs.com/favicon.ico",
        "vod3.obs.co.kr": "https://www.obs.co.kr/favicon.ico",
        "www.obs.co.kr": "https://www.obs.co.kr/favicon.ico"
    ]

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.httpAdditionalHeaders = [
            "User-Agent": AppInfo.userAgent
        ]
        session = URLSession(configuration: config)
    }

    func candidates(for station: RadioStation) async -> [URL] {
        if let cached = stationCache[station.id] {
            return cached
        }

        if let inflight = inflight[station.id] {
            return await inflight.value
        }

        let task = Task<[URL], Never> {
            let resolved = await self.buildCandidates(for: station)
            self.stationCache[station.id] = resolved
            self.inflight[station.id] = nil
            return resolved
        }

        inflight[station.id] = task
        return await task.value
    }

    func resolve(for station: RadioStation) async -> URL? {
        for url in await candidates(for: station) {
            if await validatesImageURL(url) {
                return url
            }
        }
        return nil
    }

    func validatedCandidates(for station: RadioStation) async -> [URL] {
        if let url = await resolve(for: station) {
            return [url]
        }
        return []
    }

    private func buildCandidates(for station: RadioStation) async -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        func append(_ raw: String?) {
            guard let url = secureURL(from: raw),
                  seen.insert(url.absoluteString).inserted else { return }
            urls.append(url)
        }

        for curated in curatedByName(station.name) {
            append(curated)
        }

        if let homepage = station.homepage {
            for host in hostKeys(from: homepage) {
                append(Self.curatedByHost[host])
            }
        }

        append(station.favicon)

        if let homepage = station.homepage {
            if urls.isEmpty {
                let discovered = await discoverFromHomepage(homepage)
                for url in discovered {
                    append(url.absoluteString)
                }
            }

            if let host = normalizedHost(from: homepage) {
                append("https://www.google.com/s2/favicons?domain=\(host)&sz=128")
            }
        }

        return urls
    }

    private func validatesImageURL(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  !data.isEmpty else {
                return false
            }
            return UIImage(data: data) != nil
        } catch {
            return false
        }
    }

    private func discoverFromHomepage(_ homepage: String) async -> [URL] {
        let cacheKey = homepage.lowercased()
        if let cached = homepageCache[cacheKey] {
            return cached
        }

        guard let pageURL = secureURL(from: homepage) else { return [] }

        do {
            let (data, response) = try await session.data(from: pageURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }

            guard let html = String(data: data.prefix(120_000), encoding: .utf8)
                ?? String(data: data.prefix(120_000), encoding: .ascii) else {
                return []
            }

            let patterns = [
                #"<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']"#,
                #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']"#,
                #"<link[^>]+rel=["']apple-touch-icon(?:-precomposed)?["'][^>]+href=["']([^"']+)["']"#,
                #"<link[^>]+href=["']([^"']+)["'][^>]+rel=["']apple-touch-icon(?:-precomposed)?["']"#,
                #"<link[^>]+rel=["'](?:shortcut )?icon["'][^>]+href=["']([^"']+)["']"#,
                #"<link[^>]+href=["']([^"']+)["'][^>]+rel=["'](?:shortcut )?icon["']"#
            ]

            var discovered: [URL] = []
            var seen = Set<String>()

            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                    continue
                }

                let range = NSRange(html.startIndex..<html.endIndex, in: html)
                for match in regex.matches(in: html, range: range) {
                    guard match.numberOfRanges > 1,
                          let valueRange = Range(match.range(at: 1), in: html) else { continue }

                    let value = String(html[valueRange])
                    guard let resolved = resolveURL(value, relativeTo: pageURL),
                          resolved.scheme == "https",
                          seen.insert(resolved.absoluteString).inserted else { continue }
                    discovered.append(resolved)
                }
            }

            homepageCache[cacheKey] = discovered
            return discovered
        } catch {
            return []
        }
    }

    private func curatedByName(_ name: String) -> [String] {
        let normalized = name.lowercased()

        if normalized.contains("kbs") {
            return [Self.curatedByHost["www.kbs.co.kr"]].compactMap { $0 }
        }
        if normalized.contains("mbc") {
            return [Self.curatedByHost["www.imbc.com"]].compactMap { $0 }
        }
        if normalized.contains("sbs") {
            return [Self.curatedByHost["www.sbs.co.kr"]].compactMap { $0 }
        }
        if normalized.contains("cbs") {
            return [Self.curatedByHost["www.cbs.co.kr"]].compactMap { $0 }
        }
        if normalized.contains("arirang") {
            return [Self.curatedByHost["www.arirang.com"]].compactMap { $0 }
        }
        if normalized.contains("ebs") {
            return [Self.curatedByHost["www.ebs.co.kr"]].compactMap { $0 }
        }
        if normalized.contains("tbs") {
            return [Self.curatedByHost["www.tbs.seoul.kr"]].compactMap { $0 }
        }
        if normalized.contains("ytn") {
            return [Self.curatedByHost["www.ytn.co.kr"]].compactMap { $0 }
        }

        return []
    }

    private func hostKeys(from homepage: String) -> [String] {
        guard let host = normalizedHost(from: homepage) else { return [] }

        var keys = [host]
        if host.hasPrefix("www.") {
            keys.append(String(host.dropFirst(4)))
        } else {
            keys.append("www.\(host)")
        }
        return keys
    }

    private func normalizedHost(from homepage: String) -> String? {
        guard let url = URL(string: homepage), let host = url.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        return host
    }

    private func resolveURL(_ value: String, relativeTo base: URL) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let absolute = URL(string: trimmed), absolute.scheme?.hasPrefix("http") == true {
            return secureURL(from: absolute.absoluteString)
        }

        guard let resolved = URL(string: trimmed, relativeTo: base)?.absoluteURL else { return nil }
        return secureURL(from: resolved.absoluteString)
    }

    private func secureURL(from raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        if scheme == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            return components.url
        }

        return scheme == "https" ? url : nil
    }
}
