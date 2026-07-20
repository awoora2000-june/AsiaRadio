import SwiftUI

struct RecentContentView: View {
    @EnvironmentObject private var player: AudioPlayerService
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var recent: RecentStore

    let searchText: String
    let onShowInfo: (RadioStation) -> Void

    private var displayedStations: [RadioStation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return recent.recentStations }

        return recent.recentStations.filter {
            $0.name.lowercased().contains(query) ||
            $0.displayFrequency.lowercased().contains(query) ||
            ($0.tags?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        Group {
            if recent.isEmpty {
                ContentUnavailableView {
                    Label("No Recent Plays", systemImage: "clock")
                } description: {
                    Text("Recently played stations will appear here.")
                }
            } else if displayedStations.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(displayedStations) { station in
                        StationRowView(
                            station: station,
                            isPlaying: player.currentStation?.id == station.id && player.isPlaying,
                            isFavorite: favorites.isFavorite(station),
                            onPlay: { player.play(station: station, in: displayedStations) },
                            onToggleFavorite: { favorites.toggle(station) },
                            onShowInfo: { onShowInfo(station) }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                recent.remove(station)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
        .listStyle(.plain)
        .listRowSpacing(4)
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(.top, 0, for: .scrollContent)
            }
        }
    }
}

#Preview {
    RecentContentView(searchText: "", onShowInfo: { _ in })
        .environmentObject(AudioPlayerService.shared)
        .environmentObject(FavoritesStore())
        .environmentObject(RecentStore())
}
