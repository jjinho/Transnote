import AVFoundation
import Foundation

@MainActor
final class AudioPlayerService {
    nonisolated init() {}

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var segmentEndTime: TimeInterval = 0
    private var onFinished: (() -> Void)?
    private var pendingStartTime: TimeInterval?
    /// Playback generation number. Incremented on every playSegment call and used to ignore stale seek completion callbacks.
    private var playbackGeneration = 0
    /// Generation number corresponding to pendingStartTime. Used when starting via status observation.
    private var pendingPlaybackGeneration = 0

    private(set) var isPlaying = false
    private(set) var loadedURL: URL?
    /// Current playback position in seconds. Retains the last value when not playing.
    private(set) var currentPlaybackTime: TimeInterval = 0
    /// Duration in seconds of the currently loaded audio.
    private(set) var duration: TimeInterval = 0
    /// Callback on playback position updates (current seconds, segment length in seconds).
    var onPlaybackTimeUpdate: ((TimeInterval, TimeInterval) -> Void)?

    var hasActiveTimeObserver: Bool {
        timeObserver != nil
    }

    func load(url: URL) {
        stop(resetPlayer: false)
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        loadedURL = url
        currentPlaybackTime = 0
        duration = 0
    }

    func playSegment(
        start: TimeInterval,
        end: TimeInterval,
        onFinished: (() -> Void)? = nil
    ) {
        clearSegmentPlayback()
        cancelStatusObservation()

        guard let player else {
            AppLogger.error("Audio playback failed: player is not loaded", logger: AppLogger.general)
            return
        }

        guard end > start else {
            AppLogger.error("Audio playback failed: invalid segment range \(start)-\(end)", logger: AppLogger.general)
            onFinished?()
            return
        }

        segmentEndTime = end
        self.onFinished = onFinished
        pendingStartTime = start
        // Advance the generation for each new playback request (to invalidate stale seek callbacks)
        playbackGeneration += 1
        let generation = playbackGeneration

        if let item = player.currentItem, item.status == .readyToPlay {
            beginPlayback(at: start, generation: generation)
        } else if let item = player.currentItem {
            pendingPlaybackGeneration = generation
            statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                Task { @MainActor in
                    self?.handlePlayerItemStatusChange(item)
                }
            }
        } else {
            AppLogger.error("Audio playback failed: player item is missing", logger: AppLogger.general)
            onFinished?()
        }
    }

    /// Pauses playback (keeping the current position).
    func pause() {
        guard isPlaying else { return }
        player?.pause()
        isPlaying = false
    }

    /// Resumes from pause.
    func resume() {
        guard !isPlaying, let player else { return }
        player.play()
        isPlaying = true
    }

    func stop() {
        stop(resetPlayer: true)
    }

    private func stop(resetPlayer: Bool) {
        clearSegmentPlayback()
        cancelStatusObservation()
        player?.pause()
        isPlaying = false
        segmentEndTime = 0
        pendingStartTime = nil
        pendingPlaybackGeneration = 0

        if resetPlayer {
            player = nil
            loadedURL = nil
        }
    }

    private func handlePlayerItemStatusChange(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            cancelStatusObservation()
            if let start = pendingStartTime {
                beginPlayback(at: start, generation: pendingPlaybackGeneration)
            }
        case .failed:
            cancelStatusObservation()
            let message = item.error?.localizedDescription ?? "unknown error"
            AppLogger.error("Audio playback failed to load: \(message)", logger: AppLogger.general)
            finishSegmentPlayback()
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func beginPlayback(at start: TimeInterval, generation: Int) {
        guard let player else { return }

        let startTime = CMTime(seconds: start, preferredTimescale: 600)
        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                // Ignore completion callbacks from stale seeks (when the generation differs)
                guard let self else { return }
                guard self.playbackGeneration == generation else { return }

                guard finished else {
                    // The seek was interrupted by another seek. Do nothing here rather than treating it as complete
                    return
                }
                self.player?.play()
                self.isPlaying = true
                self.installTimeObserver()
            }
        }
    }

    private func installTimeObserver() {
        guard let player else { return }

        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentPlaybackTime = time.seconds
            let itemDuration = self.player?.currentItem?.duration.seconds ?? 0
            if itemDuration.isFinite && itemDuration > 0 {
                self.duration = itemDuration
            }
            self.onPlaybackTimeUpdate?(time.seconds, self.segmentEndTime)
            if time.seconds >= self.segmentEndTime {
                self.finishSegmentPlayback()
            }
        }
    }

    private func finishSegmentPlayback() {
        let callback = onFinished
        clearSegmentPlayback()
        cancelStatusObservation()
        pendingStartTime = nil
        pendingPlaybackGeneration = 0
        player?.pause()
        isPlaying = false
        callback?()
    }

    private func clearSegmentPlayback() {
        removeTimeObserver()
        player?.pause()
        isPlaying = false
        onFinished = nil
        pendingStartTime = nil
        pendingPlaybackGeneration = 0
    }

    private func cancelStatusObservation() {
        statusObservation = nil
    }

    private func removeTimeObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }
}
