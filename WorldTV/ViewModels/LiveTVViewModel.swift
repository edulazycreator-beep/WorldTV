import Combine
import Foundation

/// Coordinates what is playing: the active channel list (for previous/next),
/// the player, and watch-history bookkeeping.
@MainActor
final class LiveTVViewModel: ObservableObject {
    @Published private(set) var queue: [Channel] = []
    @Published private(set) var current: Channel?
    @Published var queueTitle = "All Channels"

    let player: PlayerController
    private let library: LibraryStore
    private var sessionID: UUID?
    private var cancellables: Set<AnyCancellable> = []

    init(player: PlayerController, library: LibraryStore) {
        self.player = player
        self.library = library
        applySettings(library.settings)
        library.$settings
            .dropFirst()
            .sink { [weak self] settings in self?.applySettings(settings) }
            .store(in: &cancellables)
    }

    private func applySettings(_ settings: AppSettings) {
        player.maxReconnectAttempts = max(0, settings.reconnectAttempts)
    }

    /// Plays `channel`. `list` becomes the queue used by previous/next.
    func play(_ channel: Channel, in list: [Channel]? = nil, title: String? = nil) {
        if let list, !list.isEmpty {
            queue = list
            if let title { queueTitle = title }
        }
        if !queue.contains(where: { $0.id == channel.id }) {
            queue.insert(channel, at: 0)
        }
        endSession()
        let settings = library.settings
        if current == nil {
            // First playback of the session: apply the user's default audio settings.
            player.volume = Float(settings.defaultVolume)
            player.isMuted = settings.startMuted
        }
        current = channel
        player.play(channel, preferHighestQuality: settings.preferHighestQuality,
                    autoPlay: settings.autoplayOnSelect)
        sessionID = library.recordPlay(channel)
    }

    func setQueue(_ list: [Channel], title: String) {
        queue = list
        queueTitle = title
    }

    func next() { step(1) }
    func previous() { step(-1) }

    private func step(_ delta: Int) {
        guard !queue.isEmpty else { return }
        let index = current.flatMap { channel in queue.firstIndex { $0.id == channel.id } } ?? -delta
        let target = (index + delta + queue.count) % queue.count
        play(queue[target])
    }

    func stop() {
        endSession()
        player.stop()
        current = nil
    }

    private func endSession() {
        if let sessionID { library.finishSession(sessionID) }
        sessionID = nil
    }

    var canStep: Bool { queue.count > 1 }
}
