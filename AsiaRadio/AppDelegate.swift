import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.beginReceivingRemoteControlEvents()
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            NowPlayingManager.shared.activateSession()

            // Cold launch from a delivered Wake Radio notification.
            if let response = launchOptions?[.remoteNotification] as? [AnyHashable: Any],
               response["type"] as? String == "wake_alarm" {
                WakeAlarmStore.shared.handleNotificationResponse()
            }
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task { @MainActor in
            NowPlayingManager.shared.reactivateSession()
            WakeAlarmStore.shared.checkMissedAlarmOnForeground()
            WakeAlarmStore.shared.rescheduleIfNeeded()
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Task { @MainActor in
            WakeAlarmStore.shared.prepareForBackground()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if notification.request.content.userInfo["type"] as? String == "wake_alarm" {
            await MainActor.run {
                NowPlayingManager.shared.activateSession()
                NowPlayingManager.shared.reactivateSession()
                // Auto-play only — no banner / alarm UI.
                WakeAlarmStore.shared.startWakeRadio(force: true)
            }
            return []
        }
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.notification.request.content.userInfo["type"] as? String == "wake_alarm" {
            await MainActor.run {
                NowPlayingManager.shared.activateSession()
                NowPlayingManager.shared.reactivateSession()
                WakeAlarmStore.shared.startWakeRadio(force: true)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                NowPlayingManager.shared.reactivateSession()
                WakeAlarmStore.shared.ensurePlayback()
            }
        }
    }
}
