import SwiftUI

@main
struct AsiaRadioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var player = AudioPlayerService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .environmentObject(PremiumManager.shared)
                .task {
                    await RadioBrowserAPI.shared.prefetch()
                    if let cached = await RadioBrowserAPI.shared.cachedAllStations() {
                        player.updateAllStationsQueueFallback(cached)
                    }
                }
        }
    }
}
