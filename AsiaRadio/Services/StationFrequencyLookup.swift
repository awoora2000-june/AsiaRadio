import Foundation

enum StationFrequencyLookup {
    private struct Entry {
        let keywords: [String]
        let frequency: String

        func matches(_ name: String) -> Bool {
            keywords.contains { name.contains($0) }
        }
    }

    private static let korea: [Entry] = [
        Entry(keywords: ["kbs cool", "kbs 2radio", "kbs 2fm", "kbs 2방송", "cool fm"], frequency: "89.1 MHz"),
        Entry(keywords: ["kbs classic", "kbs 3radio", "kbs 3fm", "kbs 3방송", "kbs fm"], frequency: "93.1 MHz"),
        Entry(keywords: ["kbs 1radio", "kbs 1fm", "kbs 1방송", "kbs 1r"], frequency: "97.3 MHz"),
        Entry(keywords: ["mbc fm4u", "fm4u", "fm for you의"], frequency: "91.9 MHz"),
        Entry(keywords: ["mbc fm for you", "mbc 표준", "mbc standard", "mbc fm"], frequency: "95.9 MHz"),
        Entry(keywords: ["sbs power", "파워fm"], frequency: "107.7 MHz"),
        Entry(keywords: ["sbs love", "러브fm"], frequency: "103.5 MHz"),
        Entry(keywords: ["cbs music", "cbs 음악", "cbs939"], frequency: "93.9 MHz"),
        Entry(keywords: ["cbs joy", "cbs 표준", "cbs 기독", "cbs101"], frequency: "101.7 MHz"),
        Entry(keywords: ["cbs gaspel", "cbs 가톨릭", "cbs 가스펠"], frequency: "98.1 MHz"),
        Entry(keywords: ["tbs fm", "tbs efm"], frequency: "95.1 MHz"),
        Entry(keywords: ["arirang"], frequency: "91.5 MHz"),
        Entry(keywords: ["bbs 불교", "bbs fm"], frequency: "101.9 MHz"),
        Entry(keywords: ["cpbc", "가톨릭평화방송"], frequency: "105.3 MHz"),
        Entry(keywords: ["febc", "극동방송"], frequency: "106.5 MHz"),
        Entry(keywords: ["국방fm", "국방방송"], frequency: "96.7 MHz"),
        Entry(keywords: ["obs 라디오", "obs fm"], frequency: "90.7 MHz"),
        Entry(keywords: ["gfn", "gugak fm", "국악방송"], frequency: "99.1 MHz")
    ]

    private static let japan: [Entry] = [
        Entry(keywords: ["nhk fm", "nhk-fm", "ニッポン放送"], frequency: "82.5 MHz"),
        Entry(keywords: ["j-wave", "jwave", "ジェイウェイブ"], frequency: "81.3 MHz"),
        Entry(keywords: ["tokyo fm", "tokyofm", "トーキョーfm"], frequency: "80.0 MHz"),
        Entry(keywords: ["interfm", "inter fm", "インターフm"], frequency: "89.7 MHz"),
        Entry(keywords: ["bayfm", "bay fm", "ベイfm"], frequency: "78.2 MHz"),
        Entry(keywords: ["fm802", "fm 802"], frequency: "80.2 MHz"),
        Entry(keywords: ["fm cocolo", "cocolo", "ココロ"], frequency: "78.2 MHz"),
        Entry(keywords: ["fm osaka", "fmosaka"], frequency: "85.1 MHz"),
        Entry(keywords: ["kiss fm", "kiss-fm", "キスfm"], frequency: "80.4 MHz"),
        Entry(keywords: ["radio osaka", "ラジオ大阪"], frequency: "91.1 MHz"),
        Entry(keywords: ["hbc radio", "hbcラジオ"], frequency: "76.2 MHz"),
        Entry(keywords: ["stvradio", "stvラジオ"], frequency: "90.6 MHz"),
        Entry(keywords: ["rcc radio", "rccラジオ"], frequency: "1350 kHz"),
        Entry(keywords: ["nippon hoso", "ニッポン放送", "joak"], frequency: "93.0 MHz"),
        Entry(keywords: ["tbs radio", "tbsラジオ"], frequency: "954 kHz"),
        Entry(keywords: ["文化放送", "bunka hoso", "qrr"], frequency: "91.6 MHz"),
        Entry(keywords: ["free fm tokyo", "free fm 80"], frequency: "80.0 MHz"),
        Entry(keywords: ["shonan beach", "shonan beach fm"], frequency: "78.9 MHz"),
        Entry(keywords: ["fm kahoku", "かほく"], frequency: "78.7 MHz"),
        Entry(keywords: ["chofu fm"], frequency: "82.4 MHz"),
        Entry(keywords: ["fm yokohama", "ヨコハマ"], frequency: "84.7 MHz"),
        Entry(keywords: ["jolf", "ジャルフ"], frequency: "81.3 MHz"),
        Entry(keywords: ["fm north wave", "north wave"], frequency: "82.5 MHz")
    ]

    static func resolve(for station: RadioStation) -> String? {
        if let parsed = extractFromText(station.name) ?? extractFromText(station.tags ?? "") {
            return parsed
        }

        let normalized = normalize(station.name)
        let entries = station.countryCode.uppercased() == "JP" ? japan : korea

        for entry in entries where entry.matches(normalized) {
            return entry.frequency
        }

        return nil
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
    }

    private static func extractFromText(_ text: String) -> String? {
        let patterns: [(String, Bool)] = [
            (#"(\d{2,3}\.\d)\s*MHz"#, false),
            (#"(\d{2,3}\.\d)\s*FM"#, false),
            (#"FM\s*(\d{2,3}\.\d)"#, false),
            (#"(\d{2,3})\s*MHz"#, false),
            (#"FM\s*(\d{2,3})(?!\d)"#, false),
            (#"(\d{3,4})\s*kHz"#, true),
            (#"(\d{3,4})\s*AM"#, true)
        ]

        for (pattern, isAM) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else {
                continue
            }

            let value = String(text[range])
            if isAM {
                return "\(value) kHz"
            }
            if value.contains(".") {
                return "\(value) MHz"
            }
            return "\(value).0 MHz"
        }

        return nil
    }
}
