import AVFoundation
import Combine
import UIKit

enum SleepTimerMode: String {
    case duration
    case scheduledTime
}

@MainActor
final class AudioPlayerService: ObservableObject {
    static let shared = AudioPlayerService()

    @Published private(set) var currentStation: RadioStation?
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var sleepTimerMinutes = 0
    @Published private(set) var sleepTimerRemainingSeconds: Int?
    @Published private(set) var sleepTimerMode: SleepTimerMode?

    private var player: AVPlayer?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var stallObserver: NSObjectProtocol?
    private var failedToPlayObserver: NSObjectProtocol?
    private var mediaResetObserver: NSObjectProtocol?
    private var lastPlaybackSignature = ""

    private var playbackTask: Task<Void, Never>?
    private var playbackGeneration = 0
    private var connectionTimeoutTask: Task<Void, Never>?
    private var sleepTimerTask: Task<Void, Never>?
    private var sleepTimerTickTask: Task<Void, Never>?
    private var sleepTimerEndsAt: Date?

    private var wantsPlayback = false
    private var playbackQueue: [RadioStation] = []
    private var allStationsQueueFallback: [RadioStation] = []
    private var currentPlaybackURL: URL?
    private var recoveryInProgress = false

    private let sleepTimerEndsAtKey = "sleep_timer_ends_at_v1"
    private let sleepTimerMinutesKey = "sleep_timer_minutes_v1"
    private let sleepTimerModeKey = "sleep_timer_mode_v1"
    private let sleepTimerScheduledHourKey = "sleep_timer_scheduled_hour_v1"
    private let sleepTimerScheduledMinuteKey = "sleep_timer_scheduled_minute_v1"

    private init() {
        NowPlayingManager.shared.configure(player: self)
        NowPlayingManager.shared.activateSession()
        observeInterruptions()
        observeRouteChanges()
        observeMediaReset()
        restoreSleepTimerIfNeeded()
    }

    func updateAllStationsQueueFallback(_ stations: [RadioStation]) {
        guard stations.count > 1 else { return }
        allStationsQueueFallback = stations
    }

    func play(station: RadioStation, in stations: [RadioStation] = []) {
        updatePlaybackQueue(with: station, stations: stations)
        if playbackQueue.count <= 1 {
            applyPlaybackQueueFallback()
        }

        if currentStation?.id == station.id, let player, wantsPlayback, player.rate > 0, isPlaying {
            return
        }

        reconnect(station: station, in: playbackQueue)
    }

    /// Full reconnect — used after pause and when switching URLs. Live streams rarely resume cleanly.
    private func reconnect(station: RadioStation, in stations: [RadioStation]) {
        updatePlaybackQueue(with: station, stations: stations)
        if playbackQueue.count <= 1 {
            applyPlaybackQueueFallback()
        }

        playbackTask?.cancel()
        connectionTimeoutTask?.cancel()
        playbackGeneration += 1
        let generation = playbackGeneration

        errorMessage = nil
        isBuffering = true
        wantsPlayback = true
        currentStation = station
        lastPlaybackSignature = ""
        NowPlayingManager.shared.activateSession()

        tearDownPlayer()
        publishPlaybackState()

        playbackTask = Task { [generation] in
            guard !Task.isCancelled else { return }
            await connect(station: station, generation: generation)
        }
    }

    @discardableResult
    func playNext() -> Bool {
        applyPlaybackQueueFallback()
        guard let nextStation = adjacentStation(offset: 1) else { return false }
        play(station: nextStation, in: playbackQueue)
        return true
    }

    @discardableResult
    func playPrevious() -> Bool {
        applyPlaybackQueueFallback()
        guard let previousStation = adjacentStation(offset: -1) else { return false }
        play(station: previousStation, in: playbackQueue)
        return true
    }

    func togglePlayPause() {
        NowPlayingManager.shared.activateSession()

        if isPlaying {
            wantsPlayback = false
            player?.pause()
            isPlaying = false
            isBuffering = false
            connectionTimeoutTask?.cancel()
            NowPlayingManager.shared.stopRefresh()
            // Pause only — do not clear wake retries / tear down; lock-screen play must resume.
            publishPlaybackState()
            return
        }

        // Resume from lock screen / mini player.
        wantsPlayback = true
        guard let station = currentStation else {
            publishPlaybackState()
            return
        }

        let queue = playbackQueue.isEmpty ? [station] : playbackQueue
        // Live radio streams usually cannot resume after pause — reconnect the station.
        reconnect(station: station, in: queue)
    }

    func stop() {
        playbackTask?.cancel()
        connectionTimeoutTask?.cancel()
        playbackGeneration += 1
        wantsPlayback = false
        lastPlaybackSignature = ""
        playbackQueue = []
        player?.pause()
        tearDownPlayer()
        currentStation = nil
        isPlaying = false
        isBuffering = false
        clearSleepTimer()
        NowPlayingManager.shared.clear()
        WakeAlarmStore.shared.noteUserStoppedPlayback()
    }

    func setSleepTimer(minutes: Int) {
        if minutes == 0 {
            clearSleepTimer()
            return
        }

        if minutes == sleepTimerMinutes,
           sleepTimerMode == .duration,
           let endsAt = sleepTimerEndsAt,
           endsAt > Date() {
            sleepTimerRemainingSeconds = Int(ceil(endsAt.timeIntervalSinceNow))
            if sleepTimerTickTask == nil {
                startSleepTimerTick()
            }
            refreshNowPlaying()
            return
        }

        let endsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        activateSleepTimer(endsAt: endsAt, mode: .duration, configuredMinutes: minutes)
    }

    func setSleepTimerUntil(time: Date) {
        let endsAt = nextOccurrence(of: time)
        guard endsAt > Date() else { return }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        activateSleepTimer(
            endsAt: endsAt,
            mode: .scheduledTime,
            configuredMinutes: nil,
            scheduledHour: components.hour,
            scheduledMinute: components.minute
        )
    }

    private func activateSleepTimer(
        endsAt: Date,
        mode: SleepTimerMode,
        configuredMinutes: Int?,
        scheduledHour: Int? = nil,
        scheduledMinute: Int? = nil
    ) {
        sleepTimerTask?.cancel()
        sleepTimerTickTask?.cancel()
        sleepTimerTask = nil
        sleepTimerTickTask = nil

        sleepTimerEndsAt = endsAt
        sleepTimerMode = mode
        sleepTimerRemainingSeconds = max(1, Int(ceil(endsAt.timeIntervalSinceNow)))
        sleepTimerMinutes = configuredMinutes ?? Int(ceil(Double(sleepTimerRemainingSeconds ?? 0) / 60.0))
        persistSleepTimer(scheduledHour: scheduledHour, scheduledMinute: scheduledMinute)

        let remaining = max(1, Int(ceil(endsAt.timeIntervalSinceNow)))
        sleepTimerTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(remaining) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.stop()
                WakeAlarmStore.shared.onSleepTimerStopped()
            }
        }

        startSleepTimerTick()
        refreshNowPlaying()
        if isPlaying {
            NowPlayingManager.shared.startRefresh()
        }
    }

    private func nextOccurrence(of time: Date) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.hour, .minute], from: time)

        var candidate = calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: 0,
            of: now
        ) ?? now

        if candidate <= now {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }

        return candidate
    }

    func addSleepTimer(minutes deltaMinutes: Int) {
        guard deltaMinutes != 0 else { return }

        if !isSleepTimerActive || sleepTimerEndsAt == nil {
            setSleepTimer(minutes: max(0, deltaMinutes))
            return
        }

        let currentRemaining = Int(ceil(sleepTimerEndsAt?.timeIntervalSinceNow ?? 0))
        let newRemaining = max(60, currentRemaining + deltaMinutes * 60)
        let newEndsAt = Date().addingTimeInterval(TimeInterval(newRemaining))

        sleepTimerTask?.cancel()
        sleepTimerTickTask?.cancel()
        sleepTimerTask = nil
        sleepTimerTickTask = nil

        sleepTimerEndsAt = newEndsAt
        sleepTimerRemainingSeconds = newRemaining
        sleepTimerMinutes = Int(ceil(Double(newRemaining) / 60.0))
        sleepTimerMode = .duration
        persistSleepTimer()

        sleepTimerTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(newRemaining) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.stop()
                WakeAlarmStore.shared.onSleepTimerStopped()
            }
        }

        startSleepTimerTick()
        refreshNowPlaying()
    }

    private func refreshNowPlaying() {
        guard let station = currentStation else { return }
        NowPlayingManager.shared.update(station: station, isPlaying: isPlaying)
    }

    private func updatePlaybackQueue(with station: RadioStation, stations: [RadioStation]) {
        if !stations.isEmpty {
            playbackQueue = stations
            return
        }

        if playbackQueue.contains(where: { $0.id == station.id }) {
            return
        }

        playbackQueue = [station]
    }

    private func applyPlaybackQueueFallback() {
        guard let currentStation else { return }
        guard playbackQueue.count <= 1 else { return }

        let cached = allStationsQueueFallback
        guard cached.count > 1 else { return }

        if cached.contains(where: { $0.id == currentStation.id }) {
            playbackQueue = cached
        } else {
            playbackQueue = [currentStation] + cached
        }
    }

    private func ensurePlaybackQueueIfNeeded() async {
        if playbackQueue.count <= 1,
           let cached = await RadioBrowserAPI.shared.cachedAllStations(),
           cached.count > 1 {
            updateAllStationsQueueFallback(cached)
        }
        applyPlaybackQueueFallback()
    }

    private func adjacentStation(offset: Int) -> RadioStation? {
        guard playbackQueue.count > 1,
              let currentStation,
              let currentIndex = playbackQueue.firstIndex(where: { $0.id == currentStation.id }) else {
            return nil
        }

        let nextIndex = (currentIndex + offset + playbackQueue.count) % playbackQueue.count
        return playbackQueue[nextIndex]
    }

    private func startSleepTimerTick() {
        sleepTimerTickTask?.cancel()
        sleepTimerTickTask = Task {
            while !Task.isCancelled {
                guard let endsAt = self.sleepTimerEndsAt else { return }
                let remaining = Int(ceil(endsAt.timeIntervalSinceNow))
                if remaining <= 0 {
                    await MainActor.run {
                        self.sleepTimerRemainingSeconds = nil
                    }
                    return
                }
                await MainActor.run {
                    self.sleepTimerRemainingSeconds = remaining
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    var formattedSleepTimerRemaining: String? {
        guard let sleepTimerRemainingSeconds, sleepTimerRemainingSeconds > 0 else { return nil }
        let minutes = sleepTimerRemainingSeconds / 60
        let seconds = sleepTimerRemainingSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    var isSleepTimerActive: Bool {
        guard let endsAt = sleepTimerEndsAt else { return false }
        return endsAt > Date()
    }

    private func clearSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTickTask?.cancel()
        sleepTimerTask = nil
        sleepTimerTickTask = nil
        sleepTimerEndsAt = nil
        sleepTimerRemainingSeconds = nil
        sleepTimerMinutes = 0
        sleepTimerMode = nil
        UserDefaults.standard.removeObject(forKey: sleepTimerEndsAtKey)
        UserDefaults.standard.removeObject(forKey: sleepTimerMinutesKey)
        UserDefaults.standard.removeObject(forKey: sleepTimerModeKey)
        UserDefaults.standard.removeObject(forKey: sleepTimerScheduledHourKey)
        UserDefaults.standard.removeObject(forKey: sleepTimerScheduledMinuteKey)
        refreshNowPlaying()
    }

    func cancelSleepTimer() {
        clearSleepTimer()
    }

    var sleepTimerEndsAtTimeString: String? {
        guard let sleepTimerEndsAt, isSleepTimerActive else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: sleepTimerEndsAt)
    }

    var savedSleepTimerScheduledTime: Date? {
        let hour = UserDefaults.standard.object(forKey: sleepTimerScheduledHourKey) as? Int
        let minute = UserDefaults.standard.object(forKey: sleepTimerScheduledMinuteKey) as? Int
        guard let hour, let minute else { return nil }

        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
    }

    private func persistSleepTimer(scheduledHour: Int? = nil, scheduledMinute: Int? = nil) {
        guard let sleepTimerEndsAt, let sleepTimerMode else { return }
        UserDefaults.standard.set(sleepTimerEndsAt.timeIntervalSince1970, forKey: sleepTimerEndsAtKey)
        UserDefaults.standard.set(sleepTimerMinutes, forKey: sleepTimerMinutesKey)
        UserDefaults.standard.set(sleepTimerMode.rawValue, forKey: sleepTimerModeKey)

        if sleepTimerMode == .scheduledTime {
            let hour = scheduledHour ?? Calendar.current.component(.hour, from: sleepTimerEndsAt)
            let minute = scheduledMinute ?? Calendar.current.component(.minute, from: sleepTimerEndsAt)
            UserDefaults.standard.set(hour, forKey: sleepTimerScheduledHourKey)
            UserDefaults.standard.set(minute, forKey: sleepTimerScheduledMinuteKey)
        } else {
            UserDefaults.standard.removeObject(forKey: sleepTimerScheduledHourKey)
            UserDefaults.standard.removeObject(forKey: sleepTimerScheduledMinuteKey)
        }
    }

    private func restoreSleepTimerIfNeeded() {
        let endsAtEpoch = UserDefaults.standard.double(forKey: sleepTimerEndsAtKey)
        let minutes = UserDefaults.standard.integer(forKey: sleepTimerMinutesKey)
        guard endsAtEpoch > 0 else { return }

        let endsAt = Date(timeIntervalSince1970: endsAtEpoch)
        guard endsAt > Date() else {
            clearSleepTimer()
            return
        }

        let mode = UserDefaults.standard.string(forKey: sleepTimerModeKey)
            .flatMap(SleepTimerMode.init(rawValue:)) ?? .duration

        sleepTimerMinutes = minutes
        sleepTimerEndsAt = endsAt
        sleepTimerMode = mode
        sleepTimerRemainingSeconds = Int(ceil(endsAt.timeIntervalSinceNow))
        startSleepTimerTick()

        sleepTimerTask?.cancel()
        sleepTimerTask = Task {
            let remaining = max(1, Int(ceil(endsAt.timeIntervalSinceNow)))
            try? await Task.sleep(nanoseconds: UInt64(remaining) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self.stop() }
        }
    }

    func prepareForBackground() {
        NowPlayingManager.shared.activateSession()
        resumeIfNeeded()
        publishPlaybackState()
    }

    func prepareForForeground() {
        NowPlayingManager.shared.activateSession()
        resumeIfNeeded()
        publishPlaybackState()
    }

    private func connect(station: RadioStation, generation: Int) async {
        guard !Task.isCancelled, generation == playbackGeneration, wantsPlayback else { return }

        await ensurePlaybackQueueIfNeeded()

        var immediateURLs: [URL] = []

        if station.countryCode.uppercased() == "KR",
           let primary = await RadioBrowserAPI.shared.resolvePrimaryKoreanURL(for: station) {
            immediateURLs.append(primary)
        }

        immediateURLs.append(contentsOf: StreamConnectionCache.orderedURLs(for: station))

        if station.countryCode.uppercased() == "JP", JapaneseStreamResolver.isNHKStation(station) {
            let nhkURLs = await RadioBrowserAPI.shared.playbackURLsForJapaneseStation(for: station)
            immediateURLs.insert(contentsOf: nhkURLs, at: 0)
        }

        immediateURLs.append(contentsOf: KoreanStreamResolver.instantURLs(for: station))
        immediateURLs = deduplicatedURLs(immediateURLs)

        if !immediateURLs.isEmpty {
            for (index, url) in immediateURLs.enumerated() {
                guard !Task.isCancelled, generation == playbackGeneration, wantsPlayback else { return }

                if index > 0 {
                    errorMessage = "Reconnecting with another URL..."
                    isBuffering = true
                    publishPlaybackState()
                }

                let timeout: UInt64 = {
                    if index == 0, isHLSStream(url: url, station: station) { return 15 }
                    return index == 0 ? 8 : 5
                }()
                let connected = await tryConnect(
                    url: url,
                    station: station,
                    generation: generation,
                    timeoutSeconds: timeout
                )
                if connected {
                    NowPlayingManager.shared.startRefresh()
                    return
                }

                if index == 0, StreamConnectionCache.isCached(stationID: station.id, url: url) {
                    StreamConnectionCache.forget(stationID: station.id)
                }

                tearDownPlayer()
            }
        }

        guard !Task.isCancelled, generation == playbackGeneration, wantsPlayback else { return }

        let urls = await RadioBrowserAPI.shared.playableURLs(for: station)
        guard !Task.isCancelled, generation == playbackGeneration, wantsPlayback else { return }

        let fallbackURLs = deduplicatedURLs(urls).filter { url in
            !immediateURLs.contains(where: { $0.absoluteString == url.absoluteString })
        }

        if fallbackURLs.isEmpty {
            if immediateURLs.isEmpty {
                failPlayback(message: "No playable stream URL available.")
            } else {
                guard generation == playbackGeneration else { return }
                failPlayback(message: "Could not connect to the stream. Try another station.")
            }
            return
        }

        for url in fallbackURLs {
            guard !Task.isCancelled, generation == playbackGeneration, wantsPlayback else { return }

            errorMessage = "Reconnecting with another URL..."
            isBuffering = true
            publishPlaybackState()

            let connected = await tryConnect(
                url: url,
                station: station,
                generation: generation,
                timeoutSeconds: 5
            )
            if connected {
                NowPlayingManager.shared.startRefresh()
                return
            }

            tearDownPlayer()
        }

        guard generation == playbackGeneration else { return }
        failPlayback(message: "Could not connect to the stream. Try another station.")
    }

    private func deduplicatedURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            let key = url.absoluteString
            guard key.hasPrefix("http"), seen.insert(key).inserted else { return false }
            return RadioStation.isLikelyStreamURL(url)
        }
    }

    private func assetOptions(for url: URL) -> [String: Any] {
        var options: [String: Any] = [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        guard let host = url.host?.lowercased() else { return options }

        var headers: [String: String] = [:]

        if host.contains("nhk") || host.contains("drdi.st") {
            headers["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
            headers["Referer"] = "https://www.nhk.or.jp/radio/"
            headers["Origin"] = "https://www.nhk.or.jp"
        } else if host.contains("mnet.x10.mx") || host.contains("x10.mx") {
            headers["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
            headers["Referer"] = "http://mnet.x10.mx/"
        }

        if !headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }
        return options
    }

    private func isHLSStream(url: URL, station: RadioStation) -> Bool {
        station.isHLS
            || url.pathExtension.lowercased() == "m3u8"
            || url.absoluteString.lowercased().contains(".m3u8")
            || url.absoluteString.lowercased().contains("nhkr.php")
    }

    private func tryConnect(
        url: URL,
        station: RadioStation,
        generation: Int,
        timeoutSeconds: UInt64 = 5
    ) async -> Bool {
        guard generation == playbackGeneration, wantsPlayback else { return false }

        let asset = AVURLAsset(
            url: url,
            options: assetOptions(for: url)
        )
        let item = AVPlayerItem(asset: asset)
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        let hlsStream = isHLSStream(url: url, station: station)
        item.preferredForwardBufferDuration = hlsStream ? 0 : (station.isHLS ? 2 : 1)

        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = !hlsStream
        player.allowsExternalPlayback = true
        if #available(iOS 15.0, *) {
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }

        self.player = player
        observePlayerItem(item)
        observePlayerRate(player, generation: generation)

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generation else { return }
                self.handleStatusChange(item.status)
            }
        }

        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generation else { return }
                self.handleTimeControlStatus(player.timeControlStatus)
            }
        }

        resumePlayback(on: player)
        startConnectionTimeout(generation: generation)

        currentPlaybackURL = url

        let connected = await waitForPlayback(generation: generation, timeoutSeconds: timeoutSeconds)
        if connected {
            StreamConnectionCache.remember(stationID: station.id, url: url)
        } else {
            currentPlaybackURL = nil
        }
        return connected
    }

    private func waitForPlayback(generation: Int, timeoutSeconds: UInt64) async -> Bool {
        let stepNanoseconds: UInt64 = 150_000_000
        let maxSteps = timeoutSeconds * 1_000_000_000 / stepNanoseconds

        for _ in 0..<maxSteps {
            if Task.isCancelled || generation != playbackGeneration || !wantsPlayback {
                return false
            }

            if let player, player.rate > 0 {
                isPlaying = true
                isBuffering = false
                errorMessage = nil
                publishPlaybackState()
                return true
            }

            if let item = player?.currentItem, item.status == .failed {
                return false
            }

            try? await Task.sleep(nanoseconds: stepNanoseconds)
        }

        return (player?.rate ?? 0) > 0
    }

    private func startConnectionTimeout(generation: Int) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled,
                  generation == playbackGeneration,
                  wantsPlayback,
                  player?.rate ?? 0 == 0 else { return }
            failPlayback(message: "Connection timed out.")
        }
    }

    private func failPlayback(message: String) {
        connectionTimeoutTask?.cancel()
        isBuffering = false
        isPlaying = false
        errorMessage = message
        publishPlaybackState()
    }

    private func resumePlayback(on player: AVPlayer) {
        if #available(iOS 15.0, *) {
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }
        player.play()
        isPlaying = player.rate > 0
        isBuffering = !isPlaying && wantsPlayback
        publishPlaybackState()
    }

    private func resumeIfNeeded() {
        guard wantsPlayback, let player else { return }
        if player.rate == 0 {
            resumePlayback(on: player)
        } else {
            isPlaying = true
            isBuffering = false
        }
        NowPlayingManager.shared.startRefresh()
        publishPlaybackState()
    }

    private func publishPlaybackState() {
        let signature = "\(currentStation?.id ?? "none")|\(isPlaying)|\(isBuffering)"
        guard signature != lastPlaybackSignature else { return }
        lastPlaybackSignature = signature

        NowPlayingManager.shared.update(station: currentStation, isPlaying: isPlaying)

        if isPlaying {
            connectionTimeoutTask?.cancel()
        }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            isPlaying = true
            isBuffering = false
            errorMessage = nil
        case .waitingToPlayAtSpecifiedRate:
            isBuffering = wantsPlayback
        case .paused:
            if wantsPlayback {
                isBuffering = true
                if UIApplication.shared.applicationState == .background {
                    resumeIfNeeded()
                }
            } else {
                isPlaying = false
                isBuffering = false
            }
        @unknown default:
            break
        }
        publishPlaybackState()
    }

    private func handleStatusChange(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            errorMessage = nil
            if wantsPlayback, let player {
                player.play()
                isPlaying = player.rate > 0
                isBuffering = !isPlaying
            }
            publishPlaybackState()
        case .failed:
            isBuffering = false
            isPlaying = false
            if errorMessage == nil {
                errorMessage = player?.currentItem?.error?.localizedDescription ?? "Playback failed."
            }
            publishPlaybackState()
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func observePlayerRate(_ player: AVPlayer, generation: Int) {
        rateObserver?.invalidate()
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generation else { return }
                if player.rate > 0 {
                    self.isPlaying = true
                    self.isBuffering = false
                    self.errorMessage = nil
                    self.publishPlaybackState()
                } else if !self.wantsPlayback {
                    self.isPlaying = false
                    self.publishPlaybackState()
                }
            }
        }
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            Task { @MainActor in
                guard let self else { return }
                if type == .began {
                    self.player?.pause()
                    self.isPlaying = false
                    self.publishPlaybackState()
                    return
                }

                NowPlayingManager.shared.reactivateSession()
                let shouldResume: Bool = {
                    guard let optionValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else {
                        return true
                    }
                    return AVAudioSession.InterruptionOptions(rawValue: optionValue).contains(.shouldResume)
                }()
                if shouldResume, self.wantsPlayback {
                    self.resumeIfNeeded()
                }
            }
        }
    }

    private func observeRouteChanges() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

            Task { @MainActor in
                switch reason {
                case .newDeviceAvailable, .categoryChange, .oldDeviceUnavailable:
                    NowPlayingManager.shared.reactivateSession()
                    if self?.wantsPlayback == true {
                        self?.resumeIfNeeded()
                    }
                default:
                    break
                }
            }
        }
    }

    private func observeMediaReset() {
        mediaResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                NowPlayingManager.shared.reactivateSession()
                self?.resumeIfNeeded()
            }
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        removePlayerItemObservers()

        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recoverPlayback() }
        }

        failedToPlayObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recoverPlayback() }
        }
    }

    private func recoverPlayback() {
        guard wantsPlayback, let station = currentStation, !recoveryInProgress else { return }

        if let url = currentPlaybackURL {
            StreamConnectionCache.forget(stationID: station.id, url: url)
        }

        recoveryInProgress = true
        playbackTask?.cancel()
        connectionTimeoutTask?.cancel()
        tearDownPlayer()
        currentPlaybackURL = nil

        let generation = playbackGeneration
        isBuffering = true
        errorMessage = "Reconnecting with another URL..."
        publishPlaybackState()
        NowPlayingManager.shared.activateSession()

        playbackTask = Task { [generation] in
            defer { self.recoveryInProgress = false }
            guard !Task.isCancelled else { return }
            await connect(station: station, generation: generation)
        }
    }

    private func removePlayerItemObservers() {
        if let stallObserver {
            NotificationCenter.default.removeObserver(stallObserver)
            self.stallObserver = nil
        }
        if let failedToPlayObserver {
            NotificationCenter.default.removeObserver(failedToPlayObserver)
            self.failedToPlayObserver = nil
        }
    }

    private func tearDownPlayer() {
        removePlayerItemObservers()
        statusObserver?.invalidate()
        timeControlObserver?.invalidate()
        rateObserver?.invalidate()
        statusObserver = nil
        timeControlObserver = nil
        rateObserver = nil
        player?.pause()
        player = nil
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        if let mediaResetObserver {
            NotificationCenter.default.removeObserver(mediaResetObserver)
        }
    }
}

@MainActor
private enum StreamConnectionCache {
    private static let defaultsKey = "stream_connection_cache_v1"
    private static var memory: [String: String] = {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }()

    static func orderedURLs(for station: RadioStation) -> [URL] {
        let baseURLs: [URL]
        if station.countryCode.uppercased() == "JP", JapaneseStreamResolver.isNHKStation(station) {
            baseURLs = station.playableURLs
        } else if station.countryCode.uppercased() == "JP" {
            baseURLs = station.prioritizedPlayableURLs
        } else {
            baseURLs = station.playableURLs
        }
        var urls = baseURLs
        guard let cached = memory[station.id], let preferred = URL(string: cached) else {
            return urls
        }

        urls.removeAll { $0.absoluteString == cached }
        return [preferred] + urls
    }

    static func remember(stationID: String, url: URL) {
        memory[stationID] = url.absoluteString
        UserDefaults.standard.set(memory, forKey: defaultsKey)
    }

    static func isCached(stationID: String, url: URL) -> Bool {
        memory[stationID] == url.absoluteString
    }

    static func forget(stationID: String) {
        memory.removeValue(forKey: stationID)
        UserDefaults.standard.set(memory, forKey: defaultsKey)
    }

    static func forget(stationID: String, url: URL) {
        guard memory[stationID] == url.absoluteString else { return }
        forget(stationID: stationID)
    }
}
