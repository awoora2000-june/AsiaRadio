import Foundation

enum AppInfo {
    static let name = "Auradio"
    static let tagline = "Asia and world radio in one place"
    static let supportedCountriesSummary = "5 regions · 24 countries"
    static let userAgent = "Auradio/1.0 (iOS; Radio App)"
    static let premiumProductId = "auradio_premium"

    /// Legal copyright holder for App Store / About.
    static let copyrightHolder = "Jwoo"
    static let copyrightYear = 2026
    static let supportEmail = "support@jwoo.dev"

    /// Public HTTPS pages (GitHub Pages from `/docs`, or root files on `main`).
    /// App Store Connect Privacy Policy & Support URLs should match these.
    static let privacyPolicyURL = URL(string: "https://awoora2000-june.github.io/AsiaRadio/privacy.html")!
    static let supportURL = URL(string: "https://awoora2000-june.github.io/AsiaRadio/support.html")!
    static let radioBrowserURL = URL(string: "https://www.radio-browser.info/")!

    static var copyrightLine: String {
        "Copyright © \(copyrightYear) \(copyrightHolder). All rights reserved."
    }

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty {
            return "\(short) (\(build))"
        }
        return short
    }
}
