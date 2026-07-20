import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var player: AudioPlayerService
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                if let station = player.currentStation {
                    StationArtworkView(station: station, size: 180)
                        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)

                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Text(station.name)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)

                            if player.isSleepTimerActive {
                                Image(systemName: "moon.zzz.fill")
                                    .font(.title3)
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("Sleep timer \(player.formattedSleepTimerRemaining ?? "")")
                            }
                        }
                        .padding(.horizontal)

                        Text(station.displayFrequency)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(station.hasFrequency ? Color("AccentColor") : .secondary)

                        if let tags = station.tags, !tags.isEmpty {
                            Text(tags)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }

                    if player.isBuffering {
                        ProgressView("Connecting to stream...")
                            .padding(.top, 8)
                    }

                    if let error = player.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    HStack(spacing: 36) {
                        Button {
                            favorites.toggle(station)
                        } label: {
                            Image(systemName: favorites.isFavorite(station) ? "heart.fill" : "heart")
                                .font(.title)
                                .foregroundStyle(favorites.isFavorite(station) ? .pink : .primary)
                        }

                        Button {
                            player.togglePlayPause()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 72))
                        }

                        if let homepage = station.homepage, let url = URL(string: homepage) {
                            Link(destination: url) {
                                Image(systemName: "safari")
                                    .font(.title)
                            }
                        } else {
                            Image(systemName: "safari")
                                .font(.title)
                                .opacity(0.3)
                        }
                    }
                    .padding(.top, 8)
                } else {
                    ContentUnavailableView("Nothing Playing", systemImage: "radio")
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    PlayerView()
        .environmentObject(AudioPlayerService.shared)
        .environmentObject(FavoritesStore())
}
