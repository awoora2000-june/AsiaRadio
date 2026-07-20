import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var player: AudioPlayerService

    let station: RadioStation
    let onOpenPlayer: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    StationArtworkView(station: station, size: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(station.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            if player.isSleepTimerActive {
                                Image(systemName: "moon.zzz.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("Sleep timer \(player.formattedSleepTimerRemaining ?? "")")
                            }
                        }

                        if player.isBuffering {
                            Text("Connecting...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label(station.displayFrequency, systemImage: "antenna.radiowaves.left.and.right")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(station.hasFrequency ? Color("AccentColor") : .secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpenPlayer)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                }
                .buttonStyle(.borderless)

                Button {
                    player.stop()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }
}

#Preview {
    MiniPlayerView(
        station: RadioStation(
            id: "1",
            name: "KBS Classic FM",
            streamURL: URL(string: "https://example.com")!,
            countryCode: "KR",
            country: "Korea"
        ),
        onOpenPlayer: {}
    )
    .environmentObject(AudioPlayerService.shared)
}
