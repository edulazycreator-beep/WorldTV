import XCTest
@testable import WorldTV

/// Exercises the player's state machine and fallback policy. Failures are
/// injected through `handlePlaybackFailure` so no real stream is needed.
@MainActor
final class PlaybackLifecycleTests: XCTestCase {
    private func channel(streams count: Int) -> Channel {
        let streams = (0..<count).map {
            StreamSource(url: URL(string: "https://unreachable.invalid/\($0).m3u8")!, quality: "\(720 - $0)p")
        }
        return TestData.channel("Test.tv", streams: streams)
    }

    func testStartsLoadingAndStopReturnsToIdle() {
        let player = PlayerController()
        player.play(channel(streams: 1))
        XCTAssertEqual(player.state, .loading)
        XCTAssertNotNil(player.activeStream)
        XCTAssertEqual(player.channel?.id, "Test.tv")

        player.stop()
        XCTAssertEqual(player.state, .idle)
        XCTAssertNil(player.channel)
        XCTAssertNil(player.activeStream)
        XCTAssertNil(player.player.currentItem)
    }

    func testChannelWithoutStreamsFailsImmediately() {
        let player = PlayerController()
        player.play(TestData.channel("Empty.tv", streams: []))
        XCTAssertEqual(player.state, .failed("This channel has no stream available."))
    }

    func testFallsBackToNextStreamBeforeReconnecting() {
        let player = PlayerController()
        player.reconnectDelay = { _ in 60 } // never fires during the test
        player.play(channel(streams: 2))
        let firstURL = player.activeStream?.url

        player.handlePlaybackFailure("boom", generation: player.generation)
        XCTAssertEqual(player.state, .loading)
        XCTAssertNotEqual(player.activeStream?.url, firstURL, "second stream is tried")

        player.handlePlaybackFailure("boom", generation: player.generation)
        XCTAssertEqual(player.state, .reconnecting(attempt: 1, of: player.maxReconnectAttempts))
        player.stop()
    }

    func testGivesUpAfterReconnectAttempts() {
        let player = PlayerController()
        player.maxReconnectAttempts = 0
        player.play(channel(streams: 1))
        player.handlePlaybackFailure("Server said no", generation: player.generation)
        XCTAssertEqual(player.state, .failed("Server said no"))
        XCTAssertEqual(player.state.errorMessage, "Server said no")
        XCTAssertNil(player.player.currentItem)
    }

    func testReconnectRestartsFromFirstStream() async throws {
        let player = PlayerController()
        player.maxReconnectAttempts = 50 // keep the test independent of real network failures
        player.reconnectDelay = { _ in 0 }
        player.play(channel(streams: 1))
        let before = player.generation
        player.handlePlaybackFailure("drop", generation: player.generation)
        XCTAssertEqual(player.state, .reconnecting(attempt: 1, of: 50))

        // Let the zero-delay reconnect task run on the main actor; a restart
        // always bumps the generation and re-selects the first stream.
        var waited = 0
        while player.generation == before && waited < 50 {
            try await Task.sleep(nanoseconds: 10_000_000)
            waited += 1
        }
        XCTAssertGreaterThan(player.generation, before)
        XCTAssertEqual(player.activeStream?.url.lastPathComponent, "0.m3u8")
        player.stop()
    }

    func testStaleCallbacksAreIgnored() {
        let player = PlayerController()
        player.maxReconnectAttempts = 0
        player.play(channel(streams: 1))
        let oldGeneration = player.generation
        player.play(channel(streams: 1)) // switching channel bumps the generation
        player.handlePlaybackFailure("late error from previous item", generation: oldGeneration)
        XCTAssertEqual(player.state, .loading, "an error from the previous stream must not fail the new one")
        player.stop()
    }

    func testRetryAfterFailureStartsAgain() {
        let player = PlayerController()
        player.maxReconnectAttempts = 0
        player.play(channel(streams: 1))
        player.handlePlaybackFailure("x", generation: player.generation)
        XCTAssertNotNil(player.state.errorMessage)
        player.retry()
        XCTAssertEqual(player.state, .loading)
        player.stop()
    }

    func testAutoPlayOffPreparesPaused() {
        let player = PlayerController()
        player.play(channel(streams: 1), autoPlay: false)
        XCTAssertEqual(player.player.rate, 0)
        player.stop()
    }

    func testStateLabels() {
        XCTAssertEqual(PlaybackState.playing.label, "Live")
        XCTAssertTrue(PlaybackState.buffering.isBusy)
        XCTAssertFalse(PlaybackState.playing.isBusy)
        XCTAssertEqual(PlaybackState.reconnecting(attempt: 2, of: 3).label, "Reconnecting (2/3)…")
    }

    func testLiveViewModelQueueNavigationAndHistory() async {
        let library = LibraryStore(store: JSONFileStore(directory: TestData.temporaryDirectory()))
        let player = PlayerController()
        let live = LiveTVViewModel(player: player, library: library)
        let list = ["A", "B", "C"].map { TestData.channel($0) }

        live.play(list[0], in: list, title: "Test")
        XCTAssertEqual(live.current?.id, "A")
        live.next()
        XCTAssertEqual(live.current?.id, "B")
        live.previous()
        live.previous()
        XCTAssertEqual(live.current?.id, "C", "previous wraps around")
        XCTAssertEqual(library.library.recentChannelIDs(), ["C", "A", "B"])
        XCTAssertEqual(library.library.history.count, 4)

        live.stop()
        XCTAssertNil(live.current)
        XCTAssertEqual(player.state, .idle)
    }
}
