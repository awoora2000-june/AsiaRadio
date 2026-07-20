import Foundation

enum AppInfo {
    static let name = "Auradio"
    static let tagline = "Asia and world radio in one place"
    static let supportedCountriesSummary = "5 regions · 24 countries"
    static let userAgent = "Auradio/1.0 (iOS; Radio App)"
    static let premiumProductId = "auradio_premium"

    static let privacyPolicyURL = URL(string: "https://junewoo.github.io/AsiaRadio/privacy.html")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
