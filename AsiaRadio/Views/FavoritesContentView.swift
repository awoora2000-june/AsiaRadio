import SwiftUI

struct FavoritesContentView: View {
    @EnvironmentObject private var player: AudioPlayerService
    @EnvironmentObject private var favorites: FavoritesStore

    let searchText: String
    let onShowInfo: (RadioStation) -> Void

    private var filteredGroups: [(country: RadioCountry, stations: [RadioStation])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return favorites.groupedByCountry.compactMap { group in
            let stations: [RadioStation]
            if query.isEmpty {
                stations = group.stations
            } else {
                stations = group.stations.filter {
                    $0.name.lowercased().contains(query) ||
                    $0.displayFrequency.lowercased().contains(query) ||
                    ($0.tags?.lowercased().contains(query) ?? false)
                }
            }
            return stations.isEmpty ? nil : (group.country, stations)
        }
    }

    private var playbackQueue: [RadioStation] {
        filteredGroups.flatMap(\.stations)
    }

    var body: some View {
        Group {
            if favorites.isEmpty {
                ContentUnavailableView {
                    Label("No Favorites", systemImage: "heart.slash")
                } description: {
                    Text("Add stations to favorites from the more (⋯) menu.")
                }
            } else if filteredGroups.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(filteredGroups, id: \.country.id) { group in
                        Section {
                            ForEach(group.stations) { station in
                                StationRowView(
                                    station: station,
                                    isPlaying: player.currentStation?.id == station.id && player.isPlaying,
                                    isFavorite: true,
                                    onPlay: { player.play(station: station, in: playbackQueue) },
                                    onToggleFavorite: { favorites.toggle(station) },
                                    onShowInfo: { onShowInfo(station) }
                                )
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        favorites.toggle(station)
                                    } label: {
                                        Label("Remove", systemImage: "heart.slash")
                                    }
                                    .tint(.red)
                                }
                            }
                        } header: {
                            HStack {
                                Text("\(group.country.flag) \(group.country.title)")
                                Spacer()
                                Text("\(group.stations.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .listRowSpacing(4)
                .scrollDismissesKeyboard(.interactively)
                .contentMargins(.top, 0, for: .scrollContent)
            }
        }
    }
}

#Preview {
    FavoritesContentView(searchText: "", onShowInfo: { _ in })
        .environmentObject(AudioPlayerService.shared)
        .environmentObject(FavoritesStore())
}
