import Foundation

@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var favoriteStations: [RadioStation] = []

    private let storageKey = "favorite_stations_v2"

    init() {
        load()
    }

    var isEmpty: Bool { favoriteStations.isEmpty }

    func isFavorite(_ station: RadioStation) -> Bool {
        favoriteStations.contains { $0.id == station.id }
    }

    func toggle(_ station: RadioStation) {
        if let index = favoriteStations.firstIndex(where: { $0.id == station.id }) {
            favoriteStations.remove(at: index)
        } else {
            favoriteStations.append(station)
            favoriteStations.sort { lhs, rhs in
                if lhs.countryCode != rhs.countryCode {
                    return lhs.countryCode < rhs.countryCode
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
        persist()
    }

    func favorites(for country: RadioCountry) -> [RadioStation] {
        favoriteStations
            .filter { $0.countryCode.uppercased() == country.rawValue }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var groupedByCountry: [(country: RadioCountry, stations: [RadioStation])] {
        RadioCountry.allCases.compactMap { country in
            let stations = favorites(for: country)
            return stations.isEmpty ? nil : (country, stations)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stations = try? JSONDecoder().decode([RadioStation].self, from: data) else {
            return
        }
        favoriteStations = stations
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(favoriteStations) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
