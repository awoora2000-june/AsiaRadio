import SwiftUI

struct PopularContentView: View {
    @EnvironmentObject private var player: AudioPlayerService
    @EnvironmentObject private var favorites: FavoritesStore

    let searchText: String
    let onShowInfo: (RadioStation) -> Void

    @State private var groups: [(country: RadioCountry, stations: [RadioStation])] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filteredGroups: [(country: RadioCountry, stations: [RadioStation])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return groups.compactMap { group in
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
            if isLoading && groups.isEmpty {
                loadingView
            } else if let errorMessage, groups.isEmpty {
                errorView(message: errorMessage)
            } else if filteredGroups.isEmpty {
                emptyView
            } else {
                List {
                    ForEach(filteredGroups, id: \.country.id) { group in
                        Section {
                            ForEach(group.stations) { station in
                                StationRowView(
                                    station: station,
                                    isPlaying: player.currentStation?.id == station.id && player.isPlaying,
                                    isFavorite: favorites.isFavorite(station),
                                    onPlay: { player.play(station: station, in: playbackQueue) },
                                    onToggleFavorite: { favorites.toggle(station) },
                                    onShowInfo: { onShowInfo(station) }
                                )
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
                .overlay(alignment: .top) {
                    if isLoading {
                        ProgressView()
                            .padding(8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .refreshable {
            await loadPopular(forceRefresh: true)
        }
        .task {
            await loadPopular()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading popular stations...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label("Failed to Load", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await loadPopular() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var emptyView: some View {
        if searchText.isEmpty {
            ContentUnavailableView("No Popular Stations", systemImage: "star")
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private func loadPopular(forceRefresh: Bool = false) async {
        if !forceRefresh {
            var cached: [(RadioCountry, [RadioStation])] = []
            for country in RadioCountry.allCases {
                if let stations = await RadioBrowserAPI.shared.cachedPopularStations(for: country), !stations.isEmpty {
                    cached.append((country, stations))
                }
            }
            if !cached.isEmpty {
                groups = cached
            }
        }

        isLoading = groups.isEmpty
        errorMessage = nil
        defer { isLoading = false }

        do {
            groups = try await RadioBrowserAPI.shared.fetchPopularStations(forceRefresh: forceRefresh)
        } catch {
            if groups.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    PopularContentView(searchText: "", onShowInfo: { _ in })
        .environmentObject(AudioPlayerService.shared)
        .environmentObject(FavoritesStore())
}
