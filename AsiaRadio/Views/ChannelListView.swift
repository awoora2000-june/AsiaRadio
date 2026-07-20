import SwiftUI

struct ChannelListView: View {
    @EnvironmentObject private var player: AudioPlayerService
    @EnvironmentObject private var favorites: FavoritesStore
    @StateObject private var locationManager = LocationManager()

    let searchText: String
    let onShowInfo: (RadioStation) -> Void

    @State private var stations: [RadioStation] = []
    @State private var displayedStations: [RadioStation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var nearbyLocationMessage: String? {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            return "Location access is off. Enable it in Settings to sort by distance."
        case .authorizedWhenInUse, .authorizedAlways:
            if locationManager.location == nil {
                return "Getting your location..."
            }
            return nil
        default:
            return "Allow location access to sort nearby stations first."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let nearbyLocationMessage {
                Text(nearbyLocationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Group {
                if isLoading && stations.isEmpty {
                    loadingView
                } else if let errorMessage, stations.isEmpty {
                    errorView(message: errorMessage)
                } else if displayedStations.isEmpty {
                    emptyView
                } else {
                    channelList
                }
            }
        }
        .refreshable {
            await loadStations(forceRefresh: true)
        }
        .task {
            locationManager.requestLocationIfNeeded()
            await loadStations()
        }
        .onChange(of: searchText) { _, _ in
            updateDisplayedStations()
        }
        .onChange(of: stations) { _, _ in
            updateDisplayedStations()
        }
        .onChange(of: locationManager.location) { _, _ in
            updateDisplayedStations()
        }
    }

    private var channelList: some View {
        List(displayedStations) { station in
            StationRowView(
                station: station,
                isPlaying: player.currentStation?.id == station.id && player.isPlaying,
                isFavorite: favorites.isFavorite(station),
                onPlay: { player.play(station: station, in: displayedStations) },
                onToggleFavorite: { favorites.toggle(station) },
                onShowInfo: { onShowInfo(station) }
            )
            .listRowSeparator(.visible)
        }
        .listStyle(.plain)
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

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading stations...")
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
                Task { await loadStations() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var emptyView: some View {
        if searchText.isEmpty {
            ContentUnavailableView("No Stations", systemImage: "antenna.radiowaves.left.and.right")
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private func updateDisplayedStations() {
        let filtered = filterStations(stations, query: searchText)
        displayedStations = ChannelStationSorting.sortedByDistance(
            filtered,
            userLocation: locationManager.location
        )
    }

    private func filterStations(_ stations: [RadioStation], query: String) -> [RadioStation] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return stations }

        return stations.filter {
            $0.name.lowercased().contains(trimmed) ||
            $0.displayFrequency.lowercased().contains(trimmed) ||
            ($0.tags?.lowercased().contains(trimmed) ?? false) ||
            ($0.language?.lowercased().contains(trimmed) ?? false) ||
            $0.displayCountry.lowercased().contains(trimmed)
        }
    }

    private func loadStations(forceRefresh: Bool = false) async {
        if !forceRefresh, let cached = await RadioBrowserAPI.shared.cachedAllStations() {
            stations = cached
            updateDisplayedStations()
            player.updateAllStationsQueueFallback(cached)
        }

        isLoading = stations.isEmpty
        errorMessage = nil
        defer { isLoading = false }

        do {
            stations = try await RadioBrowserAPI.shared.fetchAllStations(forceRefresh: forceRefresh)
            updateDisplayedStations()
            player.updateAllStationsQueueFallback(stations)
        } catch {
            if stations.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    ChannelListView(searchText: "", onShowInfo: { _ in })
        .environmentObject(AudioPlayerService.shared)
        .environmentObject(FavoritesStore())
}
