import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class NowPlayingManager {
    static let shared = NowPlayingManager()

    private var refreshTask: Task<Void, Never>?
    private weak var player: AudioPlayerService?
    private var currentStationID: String?
    private var remoteArtworkByStationID: [String: UIImage] = [:]
    private var remoteArtworkLoadTask: Task<Void, Never>?
    private var artworkImageCache: [String: UIImage] = [:]
    private var lastSleepTimerActive = false
    private var isAudioSessionConfigured = false

    private init() {}

    func configure(player: AudioPlayerService) {
        self.player = player
        configureRemoteCommands()
    }

    func activateSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            if session.category != .playback {
                try session.setCategory(
                    .playback,
                    mode: .default,
                    options: [.allowAirPlay, .allowBluetoothA2DP]
                )
            }
            // Always re-activate — overnight sleep deactivates the session.
            try session.setActive(true)
            isAudioSessionConfigured = true
        } catch {
            try? session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
            try? session.setActive(true)
            isAudioSessionConfigured = true
        }
    }

    func reactivateSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
            isAudioSessionConfigured = true
        } catch {
            try? session.setActive(true)
            isAudioSessionConfigured = true
        }
    }

    func update(station: RadioStation?, isPlaying: Bool) {
        guard let station else {
            clear()
            return
        }

        let stationChanged = currentStationID != station.id
        let sleepTimerChanged = lastSleepTimerActive != (player?.isSleepTimerActive == true)

        if stationChanged {
            currentStationID = station.id
            remoteArtworkLoadTask?.cancel()
            remoteArtworkLoadTask = nil
            artworkImageCache.removeAll()
        }

        lastSleepTimerActive = player?.isSleepTimerActive == true

        applyNowPlayingInfo(for: station, isPlaying: isPlaying)

        if stationChanged || remoteArtworkByStationID[station.id] == nil {
            loadRemoteArtwork(for: station)
        } else if sleepTimerChanged {
            applyCachedArtwork(for: station, isPlaying: isPlaying)
        }
    }

    func clear() {
        currentStationID = nil
        remoteArtworkLoadTask?.cancel()
        remoteArtworkLoadTask = nil
        artworkImageCache.removeAll()
        lastSleepTimerActive = false

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        stopRefresh()
    }

    func startRefresh() {
        stopRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, let player, let station = player.currentStation else { break }
                updatePlaybackState(station: station, isPlaying: player.isPlaying)
            }
        }
    }

    func stopRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func applyNowPlayingInfo(for station: RadioStation, isPlaying: Bool) {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nowPlayingInfo(for: station, isPlaying: isPlaying)
    }

    private func updatePlaybackState(station: RadioStation, isPlaying: Bool) {
        let center = MPNowPlayingInfoCenter.default()
        guard var info = center.nowPlayingInfo else {
            update(station: station, isPlaying: isPlaying)
            return
        }

        info[MPMediaItemPropertyTitle] = station.name
        info[MPMediaItemPropertyArtist] = nowPlayingArtist(for: station)
        info[MPMediaItemPropertyAlbumTitle] = nowPlayingAlbumTitle(for: station)
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue

        center.nowPlayingInfo = info
    }

    private func nowPlayingInfo(for station: RadioStation, isPlaying: Bool) -> [String: Any] {
        [
            MPMediaItemPropertyTitle: station.name,
            MPMediaItemPropertyArtist: nowPlayingArtist(for: station),
            MPMediaItemPropertyAlbumTitle: nowPlayingAlbumTitle(for: station),
            MPMediaItemPropertyArtwork: artwork(for: station),
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
    }

    private func nowPlayingArtist(for station: RadioStation) -> String {
        station.displayFrequency
    }

    private func nowPlayingAlbumTitle(for station: RadioStation) -> String {
        station.displayCountry
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        // Square stop on lock screen ends playback entirely — keep pause only for radio.
        center.stopCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true

        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.stopCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let player = self?.player else { return }
                if player.isPlaying { return }
                // Prefer resume/reconnect even when AVPlayer was torn down after pause.
                if player.currentStation != nil {
                    player.togglePlayPause()
                }
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let player = self?.player, player.isPlaying else { return }
                player.togglePlayPause()
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Self.runOnMain {
                guard let player = self?.player else { return .commandFailed }
                return player.playNext() ? .success : .commandFailed
            }
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Self.runOnMain {
                guard let player = self?.player else { return .commandFailed }
                return player.playPrevious() ? .success : .commandFailed
            }
        }
    }

    private nonisolated static func runOnMain(
        _ work: @MainActor () -> MPRemoteCommandHandlerStatus
    ) -> MPRemoteCommandHandlerStatus {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { work() }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { work() }
        }
    }

    private func loadRemoteArtwork(for station: RadioStation) {
        remoteArtworkLoadTask?.cancel()

        remoteArtworkLoadTask = Task {
            guard let url = await StationArtworkResolver.shared.resolve(for: station) else { return }

            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let image = UIImage(data: data) else { return }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard player?.currentStation?.id == station.id else { return }
                remoteArtworkByStationID[station.id] = image
                artworkImageCache.removeAll()
                applyCachedArtwork(for: station, isPlaying: player?.isPlaying == true)
            }
        }
    }

    private func applyCachedArtwork(for station: RadioStation, isPlaying: Bool) {
        let center = MPNowPlayingInfoCenter.default()
        var info = center.nowPlayingInfo ?? nowPlayingInfo(for: station, isPlaying: isPlaying)
        info[MPMediaItemPropertyArtwork] = artwork(for: station)
        center.nowPlayingInfo = info
    }

    private func artwork(for station: RadioStation) -> MPMediaItemArtwork {
        let showSleepTimer = player?.isSleepTimerActive == true
        let image = resolvedArtworkImage(for: station, showSleepTimer: showSleepTimer)
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func resolvedArtworkImage(for station: RadioStation, showSleepTimer: Bool) -> UIImage {
        let hasRemote = remoteArtworkByStationID[station.id] != nil
        let cacheKey = "\(station.id)|\(showSleepTimer)|\(hasRemote)"
        if let cached = artworkImageCache[cacheKey] {
            return cached
        }

        let size = CGSize(width: 512, height: 512)
        let image: UIImage
        if let remote = remoteArtworkByStationID[station.id] {
            image = NowPlayingArtworkRenderer.compose(base: remote, showSleepTimer: showSleepTimer)
        } else {
            image = NowPlayingArtworkRenderer.render(
                for: station,
                size: size,
                showSleepTimer: showSleepTimer
            )
        }

        artworkImageCache[cacheKey] = image
        return image
    }
}

private enum NowPlayingArtworkRenderer {
    static func render(for station: RadioStation, size: CGSize, showSleepTimer: Bool) -> UIImage {
        let safeSize = normalizedSize(size)
        let base = placeholderImage(for: station, size: safeSize)
        return composeOnMainThread(base: base, showSleepTimer: showSleepTimer)
    }

    static func compose(base: UIImage, showSleepTimer: Bool) -> UIImage {
        composeOnMainThread(base: base, showSleepTimer: showSleepTimer)
    }

    private static func normalizedSize(_ size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else {
            return CGSize(width: 512, height: 512)
        }
        return size
    }

    private static func placeholderImage(for station: RadioStation, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let colors = [
                UIColor(red: 0.20, green: 0.36, blue: 0.88, alpha: 1).cgColor,
                UIColor(red: 0.33, green: 0.59, blue: 0.95, alpha: 1).cgColor
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            let flag = station.flagEmoji as NSString
            let font = UIFont.systemFont(ofSize: size.width * 0.35)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let textSize = flag.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            flag.draw(in: textRect, withAttributes: attributes)
        }
    }

    private static func composeOnMainThread(base: UIImage, showSleepTimer: Bool) -> UIImage {
        guard showSleepTimer else { return base }

        let size = base.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))

            let badgeSize = size.width * 0.28
            let badgeRect = CGRect(
                x: size.width - badgeSize - size.width * 0.05,
                y: size.width * 0.05,
                width: badgeSize,
                height: badgeSize
            )

            UIColor.systemOrange.setFill()
            UIBezierPath(ovalIn: badgeRect).fill()

            let symbolConfig = UIImage.SymbolConfiguration(pointSize: badgeSize * 0.42, weight: .semibold)
            if let moon = UIImage(systemName: "moon.zzz.fill", withConfiguration: symbolConfig)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let inset = badgeSize * 0.18
                moon.draw(in: badgeRect.insetBy(dx: inset, dy: inset))
            }
        }
    }
}
