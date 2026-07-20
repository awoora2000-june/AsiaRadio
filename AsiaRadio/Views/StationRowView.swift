import SwiftUI

struct StationRowView: View {
    @EnvironmentObject private var startupChannel: StartupChannelStore
    @EnvironmentObject private var wakeAlarm: WakeAlarmStore
    @EnvironmentObject private var premium: PremiumManager
    @Environment(\.dismissSearchFocus) private var dismissSearchFocus

    let station: RadioStation
    let isPlaying: Bool
    let isFavorite: Bool
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void
    let onShowInfo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                dismissSearchFocus()
                onPlay()
            } label: {
                HStack(spacing: 10) {
                    StationArtworkView(station: station)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(station.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                                .foregroundStyle(.primary)

                            if showsStartupChannelIcon {
                                Image(systemName: "house.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Color("AccentColor"))
                                    .accessibilityLabel("Startup channel")
                            }

                            if isPlaying {
                                Image(systemName: "waveform")
                                    .font(.caption2)
                                    .foregroundStyle(Color("AccentColor"))
                                    .symbolEffect(.pulse, isActive: true)
                                    .accessibilityLabel("Playing")
                            }
                        }

                        HStack(spacing: 6) {
                            Label(station.displayFrequency, systemImage: "antenna.radiowaves.left.and.right")
                                .fontWeight(station.hasFrequency ? .semibold : .regular)
                                .foregroundStyle(station.hasFrequency ? Color("AccentColor") : .secondary)

                            if let codec = station.codec, !codec.isEmpty, codec != "UNKNOWN" {
                                Text(codec.uppercased())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption2)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    deferredMenuAction(onToggleFavorite)
                } label: {
                    Label(
                        isFavorite ? "Remove Favorite" : "Favorite",
                        systemImage: isFavorite ? "heart.slash" : "heart"
                    )
                }

                if startupChannel.isEnabled {
                    let isCurrentStartup = startupChannel.isStartupChannel(station)
                    let blockRemove = isCurrentStartup && wakeAlarm.isEnabled
                    Button {
                        deferredMenuAction {
                            guard premium.isPremiumUnlocked else { return }
                            if blockRemove { return }
                            startupChannel.toggleStartupStation(station)
                        }
                    } label: {
                        Label(
                            blockRemove
                                ? "Remove Startup Channel (turn off Wake Radio first)"
                                : (isCurrentStartup ? "Remove Startup Channel" : "Set Startup Channel"),
                            systemImage: isCurrentStartup ? "house.fill" : "house"
                        )
                    }
                    .disabled(!premium.isPremiumUnlocked || blockRemove)
                }

                Button {
                    deferredMenuAction { onShowInfo() }
                } label: {
                    Label("Info", systemImage: "info.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("More options")
        }
        .animation(nil, value: isFavorite)
        .animation(nil, value: showsStartupChannelIcon)
        .animation(nil, value: isPlaying)
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 12))
    }

    private var showsStartupChannelIcon: Bool {
        premium.isPremiumUnlocked && startupChannel.isStartupChannel(station)
    }

    private func deferredMenuAction(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            action()
        }
    }
}

#Preview {
    let startupChannel = StartupChannelStore()
    let station = RadioStation(
        id: "1",
        name: "KBS Classic FM",
        streamURL: URL(string: "https://example.com")!,
        homepage: nil,
        favicon: nil,
        countryCode: "KR",
        country: "Korea",
        language: "korean",
        tags: "music",
        codec: "AAC",
        bitrate: 128,
        votes: 100
    )
    startupChannel.setStartupStation(station)

    return StationRowView(
        station: station,
        isPlaying: true,
        isFavorite: true,
        onPlay: {},
        onToggleFavorite: {},
        onShowInfo: {}
    )
    .padding()
    .environmentObject(startupChannel)
    .environmentObject(WakeAlarmStore.shared)
    .environmentObject(PremiumManager.shared)
}
