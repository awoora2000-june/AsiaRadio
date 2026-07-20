import Foundation

@MainActor
final class StartupChannelStore: ObservableObject {
    @Published private(set) var startupStation: RadioStation?
    @Published var isEnabled = false

    private let stationKey = "startup_station_v1"
    private let enabledKey = "startup_channel_enabled_v1"

    init() {
        load()
    }

    func isStartupChannel(_ station: RadioStation) -> Bool {
        startupStation?.id == station.id
    }

    func setStartupStation(_ station: RadioStation) {
        startupStation = station
        persist()
    }

    func clearStartupStation() {
        guard !WakeAlarmStore.shared.isEnabled else { return }
        startupStation = nil
        persist()
    }

    func toggleStartupStation(_ station: RadioStation) {
        if isStartupChannel(station) {
            clearStartupStation()
        } else {
            setStartupStation(station)
        }
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled, WakeAlarmStore.shared.isEnabled { return }
        isEnabled = enabled
        persist()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: stationKey),
           let station = try? JSONDecoder().decode(RadioStation.self, from: data) {
            startupStation = station
        }
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
    }

    private func persist() {
        if let station = startupStation,
           let data = try? JSONEncoder().encode(station) {
            UserDefaults.standard.set(data, forKey: stationKey)
        } else {
            UserDefaults.standard.removeObject(forKey: stationKey)
        }
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
    }
}
