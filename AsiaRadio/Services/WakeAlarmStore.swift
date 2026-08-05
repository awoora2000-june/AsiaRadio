import AVFoundation
import Foundation
import UIKit
import UserNotifications

/// One Wake Radio slot. `weekday` matches `Calendar`: 1 = Sunday … 7 = Saturday.
struct WakeDaySetting: Codable, Equatable, Identifiable {
    var weekday: Int
    var isEnabled: Bool
    var hour: Int
    var minute: Int

    var id: Int { weekday }

    static let shortLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var shortLabel: String {
        guard (1...7).contains(weekday) else { return "?" }
        return Self.shortLabels[weekday - 1]
    }

    static func defaults(hour: Int = 7, minute: Int = 0, allEnabled: Bool = true) -> [WakeDaySetting] {
        (1...7).map {
            WakeDaySetting(weekday: $0, isEnabled: allEnabled, hour: hour, minute: minute)
        }
    }

    static func normalize(_ days: [WakeDaySetting], fallbackHour: Int = 7, fallbackMinute: Int = 0) -> [WakeDaySetting] {
        let byWeekday = Dictionary(uniqueKeysWithValues: days.map { ($0.weekday, $0) })
        return (1...7).map { weekday in
            byWeekday[weekday] ?? WakeDaySetting(
                weekday: weekday,
                isEnabled: false,
                hour: fallbackHour,
                minute: fallbackMinute
            )
        }
    }
}

/// Sleep Timer weekly end-time slot. Same weekday convention as Wake Radio.
struct SleepDaySetting: Codable, Equatable, Identifiable {
    var weekday: Int
    var isEnabled: Bool
    var hour: Int
    var minute: Int

    var id: Int { weekday }

    static let shortLabels = WakeDaySetting.shortLabels

    var shortLabel: String {
        guard (1...7).contains(weekday) else { return "?" }
        return Self.shortLabels[weekday - 1]
    }

    static func defaults(hour: Int = 23, minute: Int = 0, allEnabled: Bool = false) -> [SleepDaySetting] {
        (1...7).map {
            SleepDaySetting(weekday: $0, isEnabled: allEnabled, hour: hour, minute: minute)
        }
    }

    static func normalize(_ days: [SleepDaySetting], fallbackHour: Int = 23, fallbackMinute: Int = 0) -> [SleepDaySetting] {
        let byWeekday = Dictionary(uniqueKeysWithValues: days.map { ($0.weekday, $0) })
        return (1...7).map { weekday in
            byWeekday[weekday] ?? SleepDaySetting(
                weekday: weekday,
                isEnabled: false,
                hour: fallbackHour,
                minute: fallbackMinute
            )
        }
    }
}

@MainActor
final class WakeAlarmStore: ObservableObject {
    static let shared = WakeAlarmStore()

    @Published var isEnabled = false
    @Published var days: [WakeDaySetting] = WakeDaySetting.defaults()
    @Published private(set) var authorizationDenied = false

    private let enabledKey = "wake_alarm_enabled_v1"
    private let hourKey = "wake_alarm_hour_v1"
    private let minuteKey = "wake_alarm_minute_v1"
    private let repeatsKey = "wake_alarm_repeats_v1"
    private let daysKey = "wake_alarm_days_v2"
    private let lastFiredDayKey = "wake_alarm_last_fired_day_v1"
    private let notificationID = "auradio.wake_alarm"
    private let intervalNotificationID = "auradio.wake_alarm.interval"
    static let notificationCategoryID = "WAKE_RADIO"

    private var monitorTimer: Timer?
    private var watchdogTimer: Timer?
    private var onFire: (() -> String?)?
    private var pendingFire = false
    private var playbackRetryTask: Task<Void, Never>?
    private var backgroundTaskID = UIBackgroundTaskIdentifier.invalid
    private var isWakePlaybackActive = false
    private var keepAlivePlayer: AVAudioPlayer?

    private init() {
        load()
        registerNotificationCategory()
    }

    /// Display hour for settings — prefers today's slot, else next fire, else first enabled.
    var hour: Int {
        if let today = todaysSetting, today.isEnabled { return today.hour }
        if let next = nextFireDate {
            return Calendar.current.component(.hour, from: next)
        }
        return days.first(where: \.isEnabled)?.hour ?? 7
    }

    var minute: Int {
        if let today = todaysSetting, today.isEnabled { return today.minute }
        if let next = nextFireDate {
            return Calendar.current.component(.minute, from: next)
        }
        return days.first(where: \.isEnabled)?.minute ?? 0
    }


    var hasEnabledDay: Bool {
        days.contains(where: \.isEnabled)
    }

    private var todaysSetting: WakeDaySetting? {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return days.first { $0.weekday == weekday }
    }

    var nextFireDate: Date? {
        guard isEnabled else { return nil }
        let calendar = Calendar.current
        let now = Date()
        for offset in 0..<8 {
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: dayDate)
            guard let setting = days.first(where: { $0.weekday == weekday && $0.isEnabled }) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: dayDate)
            components.hour = setting.hour
            components.minute = setting.minute
            components.second = 0
            guard let candidate = calendar.date(from: components) else { continue }
            if candidate.timeIntervalSinceNow > 3 {
                return candidate
            }
        }
        return nil
    }

    private var secondsSinceTodaysWake: TimeInterval? {
        guard isEnabled, let today = todaysSetting, today.isEnabled else { return nil }
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = today.hour
        components.minute = today.minute
        components.second = 0
        guard let todayAlarm = calendar.date(from: components) else { return nil }
        return Date().timeIntervalSince(todayAlarm)
    }

    func configure(onFire: @escaping () -> String?) {
        self.onFire = onFire
        if pendingFire {
            pendingFire = false
            startWakeRadio(force: true)
        }
        Task { await refreshSchedule() }
        startMonitor()
        refreshKeepAliveSupport()
    }

    func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        if enabled, !hasEnabledDay {
            days = WakeDaySetting.defaults(hour: 7, minute: 0, allEnabled: true)
        }
        persist()
        if enabled {
            clearFiredMarker()
        } else {
            stopKeepAliveSupport()
        }
        await refreshSchedule()
        startMonitor()
        refreshKeepAliveSupport()
    }

    func updateDays(_ newDays: [WakeDaySetting]) async {
        days = WakeDaySetting.normalize(newDays)
        persist()
        clearFiredMarker()
        if isEnabled {
            await refreshSchedule()
            startMonitor()
            refreshKeepAliveSupport()
        }
    }

    func handleNotificationResponse() {
        startWakeRadio(force: true)
    }

    /// Mini player stop / pause — cancel wake retries so radio does not keep restarting.
    func noteUserStoppedPlayback() {
        isWakePlaybackActive = false
        playbackRetryTask?.cancel()
        playbackRetryTask = nil
        stopKeepAlivePlayer()
        endWakeBackgroundTask()
    }

    func ensurePlayback() {
        guard isWakePlaybackActive else { return }
        startWakeRadio(force: false)
    }

    /// Re-register notifications when returning from background (system may drop them).
    func rescheduleIfNeeded() {
        guard isEnabled else { return }
        Task { await refreshSchedule() }
        startMonitor()
        refreshKeepAliveSupport()
    }

    /// Called when the app moves to background — arm keep-alive only near Wake Time.
    func prepareForBackground() {
        guard isEnabled else { return }
        refreshKeepAliveSupport()
    }

    /// Sleep Timer stopped — do not keep audio running all night; arm only near Wake Time.
    func onSleepTimerStopped() {
        guard isEnabled else { return }
        refreshKeepAliveSupport()
    }

    func startWakeRadio(force: Bool = false) {
        guard PremiumManager.shared.isPremiumUnlocked else { return }
        guard isEnabled || force else { return }

        let dayKey = dayStamp(for: Date())
        let last = UserDefaults.standard.string(forKey: lastFiredDayKey)
        let alreadyMarkedToday = last == dayKey

        if !force, alreadyMarkedToday, AudioPlayerService.shared.isPlaying {
            return
        }

        if onFire == nil {
            pendingFire = true
        }

        isWakePlaybackActive = true
        stopKeepAlivePlayer()
        beginWakeBackgroundTask()
        NowPlayingManager.shared.activateSession()
        NowPlayingManager.shared.reactivateSession()
        AudioPlayerService.shared.cancelSleepTimer()
        startRadioNow(forceRestart: true)

        UserDefaults.standard.set(dayKey, forKey: lastFiredDayKey)
        schedulePlaybackRetries()

        // Auto-play only — clear delivered local alerts so no leftover banners remain.
        Task {
            await cancelNotification()
            if isEnabled {
                await refreshSchedule()
            }
        }
    }

    func checkMissedAlarmOnForeground() {
        guard isEnabled else { return }
        guard let elapsed = secondsSinceTodaysWake else { return }

        // Recover shortly after the set time if the app was suspended through the trigger.
        guard elapsed >= 0, elapsed <= 600 else { return }

        let dayKey = dayStamp(for: Date())
        let alreadyHandledToday = UserDefaults.standard.string(forKey: lastFiredDayKey) == dayKey

        // Already auto-played today — do not restart after the user stopped.
        if alreadyHandledToday {
            return
        }

        startWakeRadio(force: true)
    }

    private func clearFiredMarker() {
        UserDefaults.standard.removeObject(forKey: lastFiredDayKey)
    }

    private func startRadioNow(forceRestart: Bool = false) {
        guard let station = resolveStation() else {
            _ = onFire?()
            return
        }

        if !forceRestart,
           AudioPlayerService.shared.isPlaying,
           AudioPlayerService.shared.currentStation?.id == station.id {
            return
        }

        // Prefer stored Startup Channel directly — do not wait on callbacks.
        NowPlayingManager.shared.activateSession()
        NowPlayingManager.shared.reactivateSession()
        AudioPlayerService.shared.cancelSleepTimer()
        AudioPlayerService.shared.play(station: station)
    }

    private func schedulePlaybackRetries() {
        playbackRetryTask?.cancel()
        playbackRetryTask = Task { [weak self] in
            for delayNs: UInt64 in [
                250_000_000,
                700_000_000,
                1_500_000_000,
                3_000_000_000,
                5_000_000_000,
                8_000_000_000
            ] {
                try? await Task.sleep(nanoseconds: delayNs)
                await MainActor.run {
                    guard let self else { return }
                    guard !Task.isCancelled else { return }
                    guard self.isWakePlaybackActive else { return }
                    if !AudioPlayerService.shared.isPlaying {
                        NowPlayingManager.shared.activateSession()
                        NowPlayingManager.shared.reactivateSession()
                        self.startRadioNow(forceRestart: true)
                    } else {
                        self.endWakeBackgroundTask()
                    }
                }
            }
            await MainActor.run {
                self?.endWakeBackgroundTask()
            }
        }
    }

    private func beginWakeBackgroundTask() {
        endWakeBackgroundTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "WakeRadioPlayback") { [weak self] in
            Task { @MainActor in
                self?.endWakeBackgroundTask()
            }
        }
    }

    private func endWakeBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func resolveStation() -> RadioStation? {
        if let data = UserDefaults.standard.data(forKey: "startup_station_v1"),
           let station = try? JSONDecoder().decode(RadioStation.self, from: data) {
            return station
        }
        return nil
    }


    // MARK: - Near-wake keep-alive (only ~15 min before Wake Time)

    /// How long before Wake Time we may hold a silent background session.
    private let keepAliveLeadSeconds: TimeInterval = 15 * 60

    private var isNearWakeTime: Bool {
        guard isEnabled else { return false }
        if let until = nextFireDate?.timeIntervalSinceNow {
            // Approaching next fire (usually tonight/tomorrow morning).
            if until > 0, until <= keepAliveLeadSeconds { return true }
        }
        if let elapsed = secondsSinceTodaysWake {
            // Just around today's wake (few minutes early → 3 min after).
            if elapsed >= -keepAliveLeadSeconds, elapsed <= 180 { return true }
        }
        return false
    }

    private func refreshKeepAliveSupport() {
        guard isEnabled, PremiumManager.shared.isPremiumUnlocked else {
            stopKeepAliveSupport()
            return
        }

        startWatchdog()

        if isNearWakeTime {
            startKeepAlivePlayerIfNeeded()
        } else {
            stopKeepAlivePlayer()
        }
    }

    private func stopKeepAliveSupport() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        stopKeepAlivePlayer()
    }

    private func startKeepAlivePlayerIfNeeded() {
        guard isNearWakeTime else {
            stopKeepAlivePlayer()
            return
        }
        // Real radio playback already keeps the app alive.
        if AudioPlayerService.shared.isPlaying {
            stopKeepAlivePlayer()
            return
        }
        if keepAlivePlayer?.isPlaying == true { return }

        NowPlayingManager.shared.activateSession()
        do {
            let player = try AVAudioPlayer(data: Self.silentWAVData())
            player.numberOfLoops = -1
            player.volume = 0.001
            player.prepareToPlay()
            player.play()
            keepAlivePlayer = player
        } catch {
            keepAlivePlayer = nil
        }
    }

    private func stopKeepAlivePlayer() {
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
    }

    private func startWatchdog() {
        watchdogTimer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.watchdogTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
        watchdogTick()
    }

    private func watchdogTick() {
        guard isEnabled else {
            stopKeepAliveSupport()
            return
        }

        // Stay quiet outside the near-wake window.
        if !isNearWakeTime {
            stopKeepAlivePlayer()
            return
        }

        startKeepAlivePlayerIfNeeded()

        guard let elapsed = secondsSinceTodaysWake else { return }
        // Start a few seconds early so Startup Channel is already playing at Wake Time.
        guard elapsed >= -8, elapsed <= 180 else { return }

        let dayKey = dayStamp(for: Date())
        let alreadyMarkedToday = UserDefaults.standard.string(forKey: lastFiredDayKey) == dayKey
        // Once started today, do not force radio back on if the user pauses/stops it.
        if alreadyMarkedToday {
            stopKeepAlivePlayer()
            return
        }

        startWakeRadio(force: true)
    }

    /// Tiny silent WAV so background audio mode keeps the process scheduled for Wake Time.
    private static func silentWAVData(seconds: Double = 2) -> Data {
        let sampleRate = 8_000
        let sampleCount = Int(Double(sampleRate) * seconds)
        let dataSize = sampleCount * 2
        var data = Data()
        data.reserveCapacity(44 + dataSize)

        func appendUInt16(_ value: UInt16) {
            var v = value.littleEndian
            data.append(Data(bytes: &v, count: 2))
        }
        func appendUInt32(_ value: UInt32) {
            var v = value.littleEndian
            data.append(Data(bytes: &v, count: 4))
        }

        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))
        appendUInt16(2)
        appendUInt16(16)
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(UInt32(dataSize))
        data.append(Data(count: dataSize))
        return data
    }

    private func startMonitor() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        guard isEnabled, let next = nextFireDate else { return }

        // Fire slightly early so session/play can start as the clock hits Wake Time.
        let fireAt = max(next.addingTimeInterval(-5), Date().addingTimeInterval(0.3))
        let timer = Timer(fire: fireAt, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.startWakeRadio(force: true)
                self?.startMonitor()
            }
        }
        // .common keeps the timer eligible while scrolling / some background states.
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
    }

    private func registerNotificationCategory() {
        let category = UNNotificationCategory(
            identifier: Self.notificationCategoryID,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func refreshSchedule() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            // Never prompt on cold launch alone — only when Wake Radio is actually on
            // (user flipped the toggle / tapped Apply).
            guard isEnabled else {
                authorizationDenied = false
                await cancelNotification()
                return
            }
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            authorizationDenied = !granted
            if !granted { return }
        case .denied:
            authorizationDenied = true
            await cancelNotification()
            return
        default:
            authorizationDenied = false
        }

        await cancelNotification()
        guard isEnabled, hasEnabledDay else { return }

        let content = UNMutableNotificationContent()
        // Quiet trigger so iOS can start playback in background — not an alarm banner UX.
        content.title = "Auradio"
        content.body = "Playing your Startup Channel"
        content.sound = nil
        content.categoryIdentifier = Self.notificationCategoryID
        content.userInfo = ["type": "wake_alarm"]
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .passive
            content.relevanceScore = 0
        }

        // Weekly calendar trigger per enabled weekday.
        for day in days where day.isEnabled {
            var dateComponents = DateComponents()
            dateComponents.weekday = day.weekday
            dateComponents.hour = day.hour
            dateComponents.minute = day.minute
            let calendarTrigger = UNCalendarNotificationTrigger(
                dateMatching: dateComponents,
                repeats: true
            )
            let calendarRequest = UNNotificationRequest(
                identifier: weekdayNotificationID(day.weekday),
                content: content,
                trigger: calendarTrigger
            )
            try? await center.add(calendarRequest)
        }

        // Precise one-shot for the next fire (more reliable within ~24h)
        if let next = nextFireDate {
            let interval = next.timeIntervalSinceNow
            if interval > 1, interval < 24 * 60 * 60 {
                let intervalTrigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: interval,
                    repeats: false
                )
                let intervalRequest = UNNotificationRequest(
                    identifier: intervalNotificationID,
                    content: content,
                    trigger: intervalTrigger
                )
                try? await center.add(intervalRequest)
            }
        }
    }

    private func weekdayNotificationID(_ weekday: Int) -> String {
        "\(notificationID).wd.\(weekday)"
    }

    private var allNotificationIDs: [String] {
        [notificationID, intervalNotificationID] + (1...7).map { weekdayNotificationID($0) }
    }

    private func cancelNotification() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: allNotificationIDs)
        center.removeDeliveredNotifications(withIdentifiers: allNotificationIDs)
    }

    private func cancelDeliveredWakeNotifications() async {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: allNotificationIDs)
    }

    private func dayStamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func load() {
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        let legacyHour = (UserDefaults.standard.object(forKey: hourKey) as? Int) ?? 7
        let legacyMinute = (UserDefaults.standard.object(forKey: minuteKey) as? Int) ?? 0

        if let data = UserDefaults.standard.data(forKey: daysKey),
           let decoded = try? JSONDecoder().decode([WakeDaySetting].self, from: data) {
            days = WakeDaySetting.normalize(decoded, fallbackHour: legacyHour, fallbackMinute: legacyMinute)
        } else {
            let repeatsDaily: Bool
            if UserDefaults.standard.object(forKey: repeatsKey) == nil {
                repeatsDaily = true
            } else {
                repeatsDaily = UserDefaults.standard.bool(forKey: repeatsKey)
            }
            days = WakeDaySetting.defaults(
                hour: legacyHour,
                minute: legacyMinute,
                allEnabled: repeatsDaily
            )
            if !repeatsDaily {
                let today = Calendar.current.component(.weekday, from: Date())
                days = days.map {
                    var copy = $0
                    copy.isEnabled = $0.weekday == today
                    return copy
                }
            }
        }
    }

    private func persist() {
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        if let data = try? JSONEncoder().encode(days) {
            UserDefaults.standard.set(data, forKey: daysKey)
        }
        // Keep legacy keys in sync for older overlays / migration safety.
        UserDefaults.standard.set(hour, forKey: hourKey)
        UserDefaults.standard.set(minute, forKey: minuteKey)
        UserDefaults.standard.set(hasEnabledDay && days.filter(\.isEnabled).count == 7, forKey: repeatsKey)
    }
}
