import AVFoundation
import Combine
import Foundation

enum PlaybackState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case reconnecting(attempt: Int, of: Int)
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .loading: return "Loading…"
        case .playing: return "Live"
        case .paused: return "Paused"
        case .buffering: return "Buffering…"
        case .reconnecting(let attempt, let total): return "Reconnecting (\(attempt)/\(total))…"
        case .failed: return "Unavailable"
        }
    }

    var isBusy: Bool {
        switch self {
        case .loading, .buffering, .reconnecting: return true
        default: return false
        }
    }

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Wraps `AVPlayer` with live-TV behaviour: stream fallback, automatic
/// reconnect with backoff, stall detection and quality reporting.
@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var channel: Channel?
    @Published private(set) var activeStream: StreamSource?
    @Published private(set) var resolution: CGSize = .zero
    @Published private(set) var bitrate: Double = 0
    @Published var volume: Float = 0.8 { didSet { player.volume = volume } }
    @Published var isMuted = false { didSet { player.isMuted = isMuted } }

    let player = AVPlayer()

    /// How many reconnect rounds to attempt after every stream has failed.
    var maxReconnectAttempts = 3
    /// Delay before reconnect round `n` (1-based).
    var reconnectDelay: (Int) -> TimeInterval = { attempt in min(8, pow(2, Double(attempt - 1))) }
    /// Seconds a stall may last before the stream is considered broken.
    var stallTimeout: TimeInterval = 20

    private var streams: [StreamSource] = []
    private var streamIndex = 0
    private var reconnectAttempt = 0
    /// Incremented on every load so callbacks from an old item are ignored.
    private(set) var generation = 0
    private var itemObservations: [NSKeyValueObservation] = []
    private var playerObservations: [NSKeyValueObservation] = []
    private var notificationTokens: [NSObjectProtocol] = []
    private var pendingTask: Task<Void, Never>?
    private var userPaused = false

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = true
        player.preventsDisplaySleepDuringVideoPlayback = true
        let observation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in self?.handleTimeControl(status) }
        }
        playerObservations = [observation]
    }

    // MARK: Public API

    var qualityLabel: String? {
        if resolution.height > 0 { return "\(Int(resolution.height))p" }
        return activeStream?.quality
    }

    /// Starts `channel`. With `autoPlay` false the stream is prepared but left paused.
    func play(_ channel: Channel, preferHighestQuality: Bool = true, autoPlay: Bool = true) {
        stopInternal(resetChannel: false)
        self.channel = channel
        streams = preferHighestQuality ? channel.rankedStreams : channel.streams
        streamIndex = 0
        reconnectAttempt = 0
        userPaused = !autoPlay
        guard !streams.isEmpty else {
            state = .failed("This channel has no stream available.")
            return
        }
        startCurrentStream()
    }

    func togglePlayPause() {
        switch state {
        case .playing, .buffering:
            userPaused = true
            player.pause()
            state = .paused
        case .paused:
            userPaused = false
            // For live streams, jump back to the live edge after a pause.
            if let item = player.currentItem, item.duration.isIndefinite,
               let range = item.seekableTimeRanges.last?.timeRangeValue {
                player.seek(to: CMTimeRangeGetEnd(range))
            }
            player.play()
        case .failed:
            retry()
        case .idle:
            if let channel { play(channel) }
        default:
            break
        }
    }

    /// Manually retries from the first stream.
    func retry() {
        guard let channel else { return }
        play(channel)
    }

    func stop() {
        stopInternal(resetChannel: true)
    }

    // MARK: Stream lifecycle

    private func startCurrentStream() {
        guard streamIndex < streams.count else { return }
        generation += 1
        let currentGeneration = generation
        let stream = streams[streamIndex]
        activeStream = stream
        resolution = .zero
        bitrate = 0
        state = .loading

        guard case .success(let url) = StreamValidator.validate(stream.url.absoluteString) else {
            handlePlaybackFailure("Invalid stream address.", generation: currentGeneration)
            return
        }

        var headers: [String: String] = [:]
        if let referrer = stream.referrer { headers["Referer"] = referrer }
        if let userAgent = stream.userAgent { headers["User-Agent"] = userAgent }
        let options: [String: Any] = headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 6
        observe(item, generation: currentGeneration)
        player.replaceCurrentItem(with: item)
        player.volume = volume
        player.isMuted = isMuted
        if userPaused { player.pause() } else { player.play() }
    }

    private func observe(_ item: AVPlayerItem, generation: Int) {
        clearItemObservers()
        let status = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.handleItemStatus(status, error: message, generation: generation)
            }
        }
        let size = item.observe(\.presentationSize, options: [.new]) { [weak self] item, _ in
            let size = item.presentationSize
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.resolution = size
            }
        }
        itemObservations = [status, size]

        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime,
                                                     object: item, queue: .main) { [weak self] note in
            let error = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            Task { @MainActor [weak self] in
                self?.handlePlaybackFailure(error ?? "Playback stopped unexpectedly.", generation: generation)
            }
        })
        notificationTokens.append(center.addObserver(forName: .AVPlayerItemPlaybackStalled,
                                                     object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleStall(generation: generation) }
        })
        notificationTokens.append(center.addObserver(forName: .AVPlayerItemNewAccessLogEntry,
                                                     object: item, queue: .main) { [weak self] note in
            let bitrate = (note.object as? AVPlayerItem)?.accessLog()?.events.last?.indicatedBitrate ?? 0
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation, bitrate > 0 else { return }
                self.bitrate = bitrate
            }
        })
        notificationTokens.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                     object: item, queue: .main) { [weak self] _ in
            // A live stream "ending" means the broadcaster dropped it: reconnect.
            Task { @MainActor [weak self] in
                self?.handlePlaybackFailure("The broadcast ended.", generation: generation)
            }
        })
    }

    private func clearItemObservers() {
        itemObservations.forEach { $0.invalidate() }
        itemObservations = []
        for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
        notificationTokens = []
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status, error: String?, generation: Int) {
        guard generation == self.generation else { return }
        switch status {
        case .readyToPlay:
            reconnectAttempt = 0
            if userPaused { state = .paused } else { player.play() }
        case .failed:
            handlePlaybackFailure(error ?? "The stream could not be opened.", generation: generation)
        default:
            break
        }
    }

    private func handleTimeControl(_ status: AVPlayer.TimeControlStatus) {
        guard channel != nil, state.errorMessage == nil else { return }
        if case .reconnecting = state { return }
        switch status {
        case .playing:
            pendingTask?.cancel()
            state = .playing
        case .waitingToPlayAtSpecifiedRate:
            if state != .loading { state = .buffering }
        case .paused:
            if userPaused { state = .paused }
        @unknown default:
            break
        }
    }

    private func handleStall(generation: Int) {
        guard generation == self.generation else { return }
        state = .buffering
        pendingTask?.cancel()
        let timeout = stallTimeout
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard let self, !Task.isCancelled, self.generation == generation,
                  self.player.timeControlStatus != .playing else { return }
            self.handlePlaybackFailure("The stream stalled.", generation: generation)
        }
    }

    /// Fallback policy: try the channel's next stream; once all have failed,
    /// run up to `maxReconnectAttempts` reconnect rounds with backoff; then fail.
    func handlePlaybackFailure(_ message: String, generation: Int) {
        guard generation == self.generation, channel != nil else { return }
        pendingTask?.cancel()

        if streamIndex + 1 < streams.count {
            streamIndex += 1
            startCurrentStream()
            return
        }

        reconnectAttempt += 1
        guard reconnectAttempt <= maxReconnectAttempts else {
            clearItemObservers()
            player.replaceCurrentItem(with: nil)
            state = .failed(message)
            return
        }

        state = .reconnecting(attempt: reconnectAttempt, of: maxReconnectAttempts)
        let delay = reconnectDelay(reconnectAttempt)
        pendingTask = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard let self, !Task.isCancelled, self.generation == generation else { return }
            self.streamIndex = 0
            self.startCurrentStream()
        }
    }

    private func stopInternal(resetChannel: Bool) {
        pendingTask?.cancel()
        pendingTask = nil
        generation += 1
        clearItemObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        activeStream = nil
        resolution = .zero
        bitrate = 0
        state = .idle
        if resetChannel { channel = nil }
    }
}
