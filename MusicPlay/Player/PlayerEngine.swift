import AVFoundation
import Combine
import Foundation
#if os(iOS)
import MediaPlayer
import UIKit
#endif

enum RepeatMode: String, CaseIterable {
    case off
    case all
    case one
}

@MainActor
final class PlayerEngine: NSObject, ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var errorMessage: String?

    @Published var volume: Double {
        didSet {
            player?.volume = Float(volume)
            UserDefaults.standard.set(volume, forKey: Self.volumeKey)
        }
    }

    @Published var shuffleEnabled = false {
        didSet {
            if shuffleEnabled {
                prepareShuffleOrder(startingAt: currentIndex)
            } else {
                shuffleOrder = []
            }
        }
    }

    @Published var repeatMode: RepeatMode = .off

    private static let volumeKey = "playerVolume"

    private var player: AVAudioPlayer?
    private var queue: [Track] = []
    private var currentIndex: Int?
    private var shuffleOrder: [Int] = []
    private var ticker: Timer?
    #if os(iOS)
    private var audioObservers: [NSObjectProtocol] = []
    private var wasPlayingBeforeInterruption = false
    #endif

    override init() {
        let saved = UserDefaults.standard.object(forKey: Self.volumeKey) as? Double ?? 0.7
        volume = min(max(saved, 0), 1)
        super.init()
        #if os(iOS)
        configureAudioSession()
        configureRemoteCommands()
        #endif
    }

    deinit {
        #if os(iOS)
        for observer in audioObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
    }

    func play(_ track: Track, in tracks: [Track]) {
        let proposedQueue = tracks.isEmpty ? [track] : tracks
        if let index = proposedQueue.firstIndex(where: { $0.id == track.id }) {
            queue = proposedQueue
            currentIndex = index
        } else {
            queue = [track]
            currentIndex = 0
        }

        if shuffleEnabled {
            prepareShuffleOrder(startingAt: currentIndex)
        }
        if let currentIndex {
            startPlayback(at: currentIndex)
        }
    }

    func togglePlayPause(fallbackQueue: [Track] = []) {
        if let player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
                stopTicker()
            } else {
                if player.currentTime >= player.duration - 0.1 {
                    player.currentTime = 0
                    currentTime = 0
                }
                if player.play() {
                    isPlaying = true
                    startTicker()
                }
            }
            updateNowPlayingInfo()
            return
        }

        if let first = fallbackQueue.first {
            play(first, in: fallbackQueue)
        }
    }

    func next() {
        guard !queue.isEmpty, currentTrack != nil else { return }
        if let index = followingIndex(automatic: false) {
            startPlayback(at: index)
        }
    }

    func previous() {
        guard !queue.isEmpty, let currentIndex else { return }

        if currentTime > 3 {
            seek(to: 0)
            return
        }

        let target: Int
        if shuffleEnabled {
            if let position = shuffleOrder.firstIndex(of: currentIndex), position > 0 {
                target = shuffleOrder[position - 1]
            } else if repeatMode == .all, let last = shuffleOrder.last {
                target = last
            } else {
                target = currentIndex
            }
        } else if currentIndex > 0 {
            target = currentIndex - 1
        } else if repeatMode == .all, !queue.isEmpty {
            target = queue.count - 1
        } else {
            target = 0
        }

        startPlayback(at: target)
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(time, 0), player.duration)
        player.currentTime = clamped
        currentTime = clamped
        updateNowPlayingInfo()
    }

    private func startPlayback(at index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        let track = queue[index]

        player?.stop()
        player = nil
        stopTicker()

        do {
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(true)
            #endif
            let newPlayer = try AVAudioPlayer(contentsOf: track.url)
            newPlayer.delegate = self
            newPlayer.volume = Float(volume)
            newPlayer.prepareToPlay()
            guard newPlayer.play() else {
                throw PlaybackError.couldNotStart
            }

            player = newPlayer
            currentTrack = track
            duration = newPlayer.duration
            currentTime = 0
            isPlaying = true
            errorMessage = nil
            startTicker()
        } catch {
            currentTrack = track
            duration = track.duration
            currentTime = 0
            isPlaying = false
            errorMessage = "无法播放“\(track.title)”，文件可能已损坏或格式不受支持。"
        }
        updateNowPlayingInfo()
    }

    private func followingIndex(automatic: Bool) -> Int? {
        guard !queue.isEmpty else { return nil }
        guard let currentIndex else { return queue.indices.first }

        if shuffleEnabled {
            if shuffleOrder.isEmpty {
                prepareShuffleOrder(startingAt: currentIndex)
            }
            if let position = shuffleOrder.firstIndex(of: currentIndex) {
                let nextPosition = position + 1
                if nextPosition < shuffleOrder.count {
                    return shuffleOrder[nextPosition]
                }
            }
            if repeatMode == .all || !automatic {
                prepareShuffleOrder(startingAt: nil)
                return shuffleOrder.first
            }
            return nil
        }

        let nextIndex = currentIndex + 1
        if nextIndex < queue.count {
            return nextIndex
        }
        if repeatMode == .all || !automatic {
            return queue.indices.first
        }
        return nil
    }

    private func prepareShuffleOrder(startingAt index: Int?) {
        guard !queue.isEmpty else {
            shuffleOrder = []
            return
        }

        var order = Array(queue.indices).shuffled()
        if let index, let position = order.firstIndex(of: index) {
            order.swapAt(0, position)
        } else if order.count > 1, let currentIndex, order.first == currentIndex {
            order.swapAt(0, Int.random(in: 1..<order.count))
        }
        shuffleOrder = order
    }

    private func handleTrackFinished() {
        guard let currentIndex else { return }

        if repeatMode == .one {
            startPlayback(at: currentIndex)
            return
        }

        if let nextIndex = followingIndex(automatic: true) {
            startPlayback(at: nextIndex)
        } else {
            isPlaying = false
            currentTime = duration
            stopTicker()
            updateNowPlayingInfo()
        }
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard let player, isPlaying else { return }
        currentTime = player.currentTime
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private enum PlaybackError: Error {
        case couldNotStart
    }

    private func updateNowPlayingInfo() {
        #if os(iOS)
        let center = MPNowPlayingInfoCenter.default()
        guard let track = currentTrack else {
            center.nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist.isEmpty ? "未知艺人" : track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if !track.album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = track.album
        }
        center.nowPlayingInfo = info

        let trackID = track.id
        let url = track.url
        Task { @MainActor [weak self] in
            guard let self, self.currentTrack?.id == trackID else { return }
            guard let image = await ArtworkCache.shared.artwork(for: url) else { return }
            var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
            current[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in
                image
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = current
        }
        #endif
    }

    #if os(iOS)
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)

        audioObservers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAudioInterruption(notification)
            }
        })

        audioObservers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleRouteChange(notification)
            }
        })
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resumePlayback() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pausePlayback() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func resumePlayback() {
        guard let player, !player.isPlaying else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if player.currentTime >= player.duration - 0.1 {
            player.currentTime = 0
            currentTime = 0
        }
        if player.play() {
            isPlaying = true
            startTicker()
            updateNowPlayingInfo()
        }
    }

    private func pausePlayback() {
        guard isPlaying else { return }
        player?.pause()
        isPlaying = false
        stopTicker()
        updateNowPlayingInfo()
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            pausePlayback()
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if options.contains(.shouldResume), wasPlayingBeforeInterruption {
                resumePlayback()
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
              reason == .oldDeviceUnavailable else { return }
        pausePlayback()
    }
    #endif
}

extension PlayerEngine: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.handleTrackFinished()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaying = false
            self.stopTicker()
            self.errorMessage = "音频解码失败：\(error?.localizedDescription ?? "未知错误")"
            self.updateNowPlayingInfo()
        }
    }
}
