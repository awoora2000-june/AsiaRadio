import SwiftUI

struct StationInfoView: View {
    let station: RadioStation
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var player: AudioPlayerService

    var body: some View {
        List {
                Section {
                    HStack(spacing: 16) {
                        StationArtworkView(station: station, size: 72)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(station.name)
                                .font(.headline)
                            Label(station.displayFrequency, systemImage: "antenna.radiowaves.left.and.right")
                                .font(.subheadline)
                                .foregroundStyle(station.hasFrequency ? Color("AccentColor") : .secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Station Info") {
                    LabeledContent("Country", value: station.displayCountry)
                    LabeledContent("Frequency", value: station.displayFrequency)
                    if let language = station.language, !language.isEmpty {
                        LabeledContent("Language", value: language)
                    }
                    if let codec = station.codec, !codec.isEmpty, codec != "UNKNOWN" {
                        LabeledContent("Codec", value: codec.uppercased())
                    }
                    if let bitrate = station.bitrate, bitrate > 0 {
                        LabeledContent("Bitrate", value: "\(bitrate) kbps")
                    }
                    if let tags = station.tags, !tags.isEmpty {
                        LabeledContent("Tags", value: tags)
                    }
                }

                Section {
                    Button {
                        player.play(station: station)
                        dismiss()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }

                    Button {
                        favorites.toggle(station)
                    } label: {
                        Label(
                            favorites.isFavorite(station) ? "Remove Favorite" : "Add Favorite",
                            systemImage: favorites.isFavorite(station) ? "heart.slash" : "heart"
                        )
                    }

                    if let url = homepageURL {
                        Link(destination: url) {
                            Label("Open Homepage", systemImage: "safari")
                        }
                    }
                }
            }
        .navigationTitle("Info")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") { dismiss() }
            }
        }
    }

    private var homepageURL: URL? {
        guard let homepage = station.homepage?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !homepage.isEmpty,
              let url = URL(string: homepage),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }
}

#Preview {
    StationInfoView(
        station: RadioStation(
            id: "1",
            name: "KBS Classic FM",
            streamURL: URL(string: "https://example.com")!,
            homepage: "https://www.kbs.co.kr",
            favicon: nil,
            countryCode: "KR",
            country: "Korea",
            language: "korean",
            tags: "classical",
            codec: "AAC",
            bitrate: 128,
            votes: 100
        )
    )
    .environmentObject(FavoritesStore())
    .environmentObject(AudioPlayerService.shared)
}
