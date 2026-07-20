import SwiftUI

struct SleepTimerIndicator: View {
    @EnvironmentObject private var player: AudioPlayerService

    var showsRemainingText = false
    var iconFont: Font = .body

    var body: some View {
        if player.isSleepTimerActive {
            if showsRemainingText {
                Label {
                    Text(player.formattedSleepTimerRemaining ?? "")
                } icon: {
                    Image(systemName: "moon.zzz.fill")
                }
                .font(iconFont)
                .foregroundStyle(.orange)
                .accessibilityLabel("Sleep timer \(player.formattedSleepTimerRemaining ?? "")")
            } else {
                Image(systemName: "moon.zzz.fill")
                    .font(iconFont)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Sleep timer \(player.formattedSleepTimerRemaining ?? "")")
            }
        }
    }
}
