import AVFoundation
import PlaybackEngine
import Testing

/// Exercises `PlayerController` against a real `AVQueuePlayer` decoding the
/// repo's fixture audio files (each ~3.03s), to verify actual decode,
/// preload-based auto-advance through the queue, and end-of-queue stopping —
/// behavior that's meaningless to fake with a mock player. Every wait below
/// is bounded (deadline-based polling, no bare sleeps) so a regression fails
/// fast instead of hanging.
@MainActor
struct PlayerControllerIntegrationTests {
    @Test func playingM4AStartsPlaybackAndAdvancesCurrentTime() async throws {
        let controller = PlayerController()
        let m4a = try await makePlayableTrack(fixture: "m4a-tagged.m4a")
        let vbr = try await makePlayableTrack(fixture: "vbr-tagged.mp3")

        controller.play([m4a, vbr])

        try await poll(timeout: .seconds(2)) {
            controller.isPlaying && controller.currentTime > 0
        }

        #expect(controller.isPlaying)
        #expect(controller.current == m4a)

        controller.stop()
    }

    @Test func naturalEndOfTrackAdvancesToTheNextQueuedTrack() async throws {
        let controller = PlayerController()
        let cbr = try await makePlayableTrack(fixture: "cbr-tagged.mp3")
        let vbr = try await makePlayableTrack(fixture: "vbr-tagged.mp3")

        controller.play([cbr, vbr])
        try await poll(timeout: .seconds(2)) { controller.isPlaying && controller.currentTime > 0 }

        controller.seek(to: cbr.duration - 0.3)

        try await poll(timeout: .seconds(3)) { controller.current == vbr }

        #expect(controller.isPlaying)

        controller.stop()
    }

    @Test func repeatOffStopsPlaybackAtTheEndOfTheQueue() async throws {
        let controller = PlayerController()
        let cbr = try await makePlayableTrack(fixture: "cbr-tagged.mp3")
        let vbr = try await makePlayableTrack(fixture: "vbr-tagged.mp3")

        controller.play([cbr, vbr])
        try await poll(timeout: .seconds(2)) { controller.isPlaying && controller.currentTime > 0 }

        // Skip straight to the last track, near its end, and let it run out.
        controller.next()
        try await poll(timeout: .seconds(2)) { controller.current == vbr }
        controller.seek(to: vbr.duration - 0.3)

        try await poll(timeout: .seconds(3)) { !controller.isPlaying }

        #expect(!controller.isPlaying)

        controller.stop()
    }
}

// MARK: - Helpers

private struct PollTimeout: Error, CustomStringConvertible {
    var description: String {
        "Timed out waiting for PlayerController condition."
    }
}

/// Polls `condition` every 50ms until it's true or `timeout` elapses,
/// throwing rather than hanging if the deadline passes.
@MainActor
private func poll(
    timeout: Duration,
    condition: @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    if condition() { return }
    throw PollTimeout()
}

/// Builds a `PlayableTrack` from a fixture file, loading its real duration
/// via `AVURLAsset` so seek-near-the-end assertions land correctly.
private func makePlayableTrack(fixture: String) async throws -> PlayableTrack {
    let url = TestFixtures.url(fixture)
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration).seconds
    return PlayableTrack(
        relativePath: fixture,
        url: url,
        title: fixture,
        artist: "Artist",
        album: "Album",
        duration: duration,
        artworkID: nil
    )
}
