import SwiftUI

struct StationArtworkView: View {
    let station: RadioStation
    var size: CGFloat = 46

    @State private var candidates: [URL] = []
    @State private var activeIndex = 0

    private var cornerRadius: CGFloat { size * 0.22 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color("AccentColor").opacity(0.15))

            if activeIndex < candidates.count {
                AsyncImage(url: candidates[activeIndex]) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color.clear
                            .onAppear { advanceCandidate() }
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: station.id) {
            activeIndex = 0
            candidates = await StationArtworkResolver.shared.validatedCandidates(for: station)
        }
    }

    private var placeholder: some View {
        Image(systemName: "music.note")
            .font(.system(size: size * 0.38))
            .foregroundStyle(Color("AccentColor"))
    }

    private func advanceCandidate() {
        guard activeIndex + 1 < candidates.count else { return }
        activeIndex += 1
    }
}
