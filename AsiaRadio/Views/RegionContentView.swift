import SwiftUI
import UIKit

struct RegionContentView: View {
    @EnvironmentObject private var player: AudioPlayerService
    @EnvironmentObject private var favorites: FavoritesStore
    @StateObject private var locationManager = LocationManager()

    let searchText: String
    let onShowInfo: (RadioStation) -> Void

    @State private var selectedCountry: RadioCountry = .korea
    @State private var stations: [RadioStation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didAutoSelectNearest = false

    private var orderedCountries: [RadioCountry] {
        CountrySorting.sortedByDistance(userLocation: locationManager.location)
    }

    private var displayedStations: [RadioStation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return stations }

        return stations.filter {
            $0.name.lowercased().contains(query) ||
            $0.displayFrequency.lowercased().contains(query) ||
            ($0.tags?.lowercased().contains(query) ?? false) ||
            ($0.language?.lowercased().contains(query) ?? false)
        }
    }

    private var locationMessage: String? {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            return "Location access is off. Countries stay in the default order."
        case .authorizedWhenInUse, .authorizedAlways:
            if locationManager.location == nil {
                return "Getting your location to sort nearby countries..."
            }
            return nil
        default:
            return "Allow location access to show nearby countries first."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let locationMessage {
                Text(locationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            countryPicker
                .padding(.bottom, 8)

            selectionHeader
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

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
            selectNearestCountryIfNeeded()
            await loadStations()
        }
        .task(id: selectedCountry) {
            await loadStations()
        }
        .onChange(of: locationManager.location) { _, _ in
            selectNearestCountryIfNeeded()
        }
    }

    private var countryPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(orderedCountries) { country in
                        countryChip(for: country)
                            .id(country.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: locationManager.location) { _, location in
                guard location != nil else { return }
                scrollCountryListToStart(proxy: proxy)
            }
            .onChange(of: didAutoSelectNearest) { _, selected in
                guard selected else { return }
                scrollCountryListToStart(proxy: proxy)
            }
        }
    }

    private func scrollCountryListToStart(proxy: ScrollViewProxy) {
        guard let first = orderedCountries.first else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(first.id, anchor: .leading)
            }
        }
    }

    private var selectionHeader: some View {
        HStack(spacing: 6) {
            Text(selectedCountry.flag)
                .font(.title3)
            Text(selectedCountry.title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            if !displayedStations.isEmpty {
                Text("\(displayedStations.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func countryChip(for country: RadioCountry) -> some View {
        let isSelected = selectedCountry == country
        return Button {
            selectedCountry = country
        } label: {
            HStack(spacing: 4) {
                Text(country.flag)
                Text(country.title)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill))
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(country.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        .id(selectedCountry.rawValue)
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
            ContentUnavailableView(
                "No Stations",
                systemImage: "antenna.radiowaves.left.and.right",
                description: Text("No stations found for \(selectedCountry.title).")
            )
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private func selectNearestCountryIfNeeded() {
        guard !didAutoSelectNearest, let location = locationManager.location else { return }
        didAutoSelectNearest = true
        if let nearest = CountrySorting.sortedByDistance(userLocation: location).first {
            selectedCountry = nearest
        }
    }

    private func loadStations(forceRefresh: Bool = false) async {
        if !forceRefresh, let cached = await RadioBrowserAPI.shared.cachedStations(for: selectedCountry) {
            stations = cached
        } else if forceRefresh {
            stations = []
        }

        isLoading = stations.isEmpty
        errorMessage = nil
        defer { isLoading = false }

        do {
            stations = try await RadioBrowserAPI.shared.fetchStations(
                country: selectedCountry,
                forceRefresh: forceRefresh
            )
        } catch {
            if stations.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    RegionContentView(searchText: "", onShowInfo: { _ in })
        .environmentObject(AudioPlayerService.shared)
        .environmentObject(FavoritesStore())
}
