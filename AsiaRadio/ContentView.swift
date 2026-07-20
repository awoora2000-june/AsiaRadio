import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var recent = RecentStore()
    @StateObject private var startupChannel = StartupChannelStore()
    @StateObject private var wakeAlarm = WakeAlarmStore.shared
    @StateObject private var premium = PremiumManager.shared
    @EnvironmentObject private var player: AudioPlayerService
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedSection: AppSection = .channels
    @State private var didAutoPlayStartupChannel = false
    @State private var searchText = ""
    @State private var infoStation: RadioStation?
    @State private var showPlayer = false
    @State private var showAbout = false
    @FocusState private var isSearchFocused: Bool

    private var sectionSpacing: CGFloat { 20.0 / UIScreen.main.scale }
    private var headerExtraTopOffset: CGFloat { 8.0 / UIScreen.main.scale }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MainHeaderBannerView()

                Spacer().frame(height: sectionSpacing)

                searchBar

                Spacer().frame(height: sectionSpacing)

                appSectionTabBar
                    .padding(.horizontal)

                Spacer().frame(height: sectionSpacing)

                Group {
                    switch selectedSection {
                    case .favorites:
                        FavoritesContentView(
                            searchText: searchText,
                            onShowInfo: showStationInfo
                        )
                    case .channels:
                        ChannelListView(
                            searchText: searchText,
                            onShowInfo: showStationInfo
                        )
                    case .region:
                        RegionContentView(
                            searchText: searchText,
                            onShowInfo: showStationInfo
                        )
                    case .recent:
                        RecentContentView(
                            searchText: searchText,
                            onShowInfo: showStationInfo
                        )
                    case .popular:
                        PopularContentView(
                            searchText: searchText,
                            onShowInfo: showStationInfo
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, headerExtraTopOffset)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showPlayer) {
                PlayerView()
            }
        }
        .environmentObject(favorites)
        .environmentObject(recent)
        .environmentObject(startupChannel)
        .environmentObject(wakeAlarm)
        .environmentObject(premium)
        .environment(\.dismissSearchFocus, dismissKeyboard)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let station = player.currentStation {
                MiniPlayerView(
                    station: station,
                    onOpenPlayer: {
                        runAfterKeyboardDismissal {
                            infoStation = nil
                            showPlayer = true
                        }
                    }
                )
                .id(station.id)
            }
        }
        .tint(Color("AccentColor"))
        .sheet(item: $infoStation, onDismiss: { infoStation = nil }) { station in
            NavigationStack {
                StationInfoView(station: station)
                    .environmentObject(favorites)
                    .environmentObject(player)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAbout) {
            NavigationStack {
                AboutContentView()
                    .environmentObject(player)
                    .environmentObject(startupChannel)
                    .environmentObject(wakeAlarm)
                    .environmentObject(premium)
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") { showAbout = false }
                        }
                    }
            }
        }
        .task {
            configureWakeAlarm()
            revokePremiumFeaturesIfNeeded()
            await tryAutoPlayStartupChannel()
        }
        .onChange(of: premium.isPremium) { _, _ in
            revokePremiumFeaturesIfNeeded()
        }
        .onChange(of: player.isPlaying) { _, isPlaying in
            if isPlaying, let station = player.currentStation {
                recent.record(station)
            }
        }
        .onChange(of: player.currentStation) { _, station in
            if station == nil {
                showPlayer = false
            }
        }
        .onChange(of: selectedSection) { _, _ in
            infoStation = nil
            showPlayer = false
            showAbout = false
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                dismissKeyboard()
                player.prepareForBackground()
                wakeAlarm.rescheduleIfNeeded()
                wakeAlarm.prepareForBackground()
            case .active:
                player.prepareForForeground()
                wakeAlarm.rescheduleIfNeeded()
                wakeAlarm.checkMissedAlarmOnForeground()
            default:
                break
            }
        }
    }

    private func configureWakeAlarm() {
        let startup = startupChannel
        wakeAlarm.configure {
            // Primary playback is handled by WakeAlarmStore via stored Startup Channel.
            // Keep this hook so pending fires after cold start still resolve a name.
            guard PremiumManager.shared.isPremiumUnlocked else { return nil }
            guard let station = startup.startupStation else { return nil }

            NowPlayingManager.shared.activateSession()
            NowPlayingManager.shared.reactivateSession()
            AudioPlayerService.shared.cancelSleepTimer()
            if !AudioPlayerService.shared.isPlaying
                || AudioPlayerService.shared.currentStation?.id != station.id {
                AudioPlayerService.shared.play(station: station)
            }
            return station.name
        }
    }

    private func tryAutoPlayStartupChannel() async {
        guard !didAutoPlayStartupChannel else { return }
        guard premium.isPremiumUnlocked else { return }
        guard startupChannel.isEnabled, let station = startupChannel.startupStation else { return }

        didAutoPlayStartupChannel = true

        if player.currentStation?.id == station.id, player.isPlaying {
            return
        }

        player.play(station: station)
    }

    private func revokePremiumFeaturesIfNeeded() {
        guard !premium.isPremiumUnlocked else { return }
        if player.isSleepTimerActive {
            player.cancelSleepTimer()
        }
        if startupChannel.isEnabled {
            startupChannel.setEnabled(false)
        }
        if wakeAlarm.isEnabled {
            Task { await wakeAlarm.setEnabled(false) }
        }
    }

    private func showStationInfo(_ station: RadioStation) {
        runAfterKeyboardDismissal {
            infoStation = station
        }
    }

    private func runAfterKeyboardDismissal(_ action: @escaping () -> Void) {
        guard isSearchFocused else {
            action()
            return
        }

        dismissKeyboard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            action()
        }
    }

    private func dismissKeyboard() {
        guard isSearchFocused else { return }
        isSearchFocused = false
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search stations", text: $searchText)
                    .focused($isSearchFocused)
                    .textContentType(.none)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { dismissKeyboard() }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            SleepTimerIndicator(iconFont: .subheadline.weight(.semibold))

            Button {
                runAfterKeyboardDismissal {
                    showAbout = true
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal)
    }
    private var appSectionTabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppSection.allCases) { section in
                Button {
                    dismissKeyboard()
                    selectedSection = section
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: section.icon)
                            .font(.system(size: 17, weight: selectedSection == section ? .semibold : .regular))
                            .symbolRenderingMode(.hierarchical)
                        Text(section.title)
                            .font(.caption2)
                            .fontWeight(selectedSection == section ? .semibold : .regular)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(selectedSection == section ? Color.accentColor : .secondary)
                    .background(
                        selectedSection == section
                            ? Color.accentColor.opacity(0.14)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    ContentView()
        .environmentObject(AudioPlayerService.shared)
}
