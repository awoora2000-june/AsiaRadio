import Foundation

@MainActor
final class RecentStore: ObservableObject {
    @Published private(set) var recentStations: [RadioStation] = []

    private let storageKey = "recent_stations_v1"
    private let maxCount = 20

    init() {
        load()
    }

    var isEmpty: Bool { recentStations.isEmpty }

    func record(_ station: RadioStation) {
        recentStations.removeAll { $0.id == station.id }
        recentStations.insert(station, at: 0)
        if recentStations.count > maxCount {
            recentStations = Array(recentStations.prefix(maxCount))
        }
        persist()
    }

    func remove(_ station: RadioStation) {
        recentStations.removeAll { $0.id == station.id }
        persist()
    }

    func clear() {
        recentStations = []
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stations = try? JSONDecoder().decode([RadioStation].self, from: data) else {
            return
        }
        recentStations = stations
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(recentStations) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
