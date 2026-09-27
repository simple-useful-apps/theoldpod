import AVFoundation
import PlaybackEngine
import Testing

/// `PlayerController` behaviors that are pure state transitions and don't
/// need to wait on real decode/playback timing (contrast with
/// `PlayerControllerIntegrationTests`, which polls a real `AVQueuePlayer`).
/// These assert synchronously right after the call that's expected to
/// produce the effect, so there's nothing to sleep or poll for.
@MainActor
struct PlayerControllerUnitTests {
    @Test func seekClampsNegativeSecondsToZero() {
        let controller = PlayerController()
        controller.play([makeTrack(duration: 10)])

        controller.seek(to: -5)

        #expect(controller.currentTime == 0)
        controller.stop()
    }

    @Test func seekClampsSecondsBeyondDurationToDuration() {
        let controller = PlayerController()
        let track = makeTrack(duration: 10)
        controller.play([track])

        controller.seek(to: 999)

        #expect(controller.currentTime == track.duration)
        controller.stop()
    }

    @Test func seekOnEmptyQueueIsANoOp() {
        let controller = PlayerController()

        controller.seek(to: 5)

        #expect(controller.currentTime == 0)
    }

    @Test func togglePlayPauseOnEmptyQueueStaysNotPlaying() {
        let controller = PlayerController()

        controller.togglePlayPause()

        #expect(!controller.isPlaying)
        #expect(controller.current == nil)
    }

    /// `playShuffled` should leave `isShuffled` on, land on some track (not
    /// necessarily the first), and never drop or duplicate a track — the
    /// underlying shuffle uses `SystemRandomNumberGenerator`, so the actual
    /// order/start isn't asserted, only that the whole set survives.
    @Test func playShuffledSetsShuffledFlagAndKeepsEveryTrack() {
        let controller = PlayerController()
        let tracks = (0 ..< 6).map { makeTrack(relativePath: "shuffled-\($0)", duration: 10) }

        controller.playShuffled(tracks)

        #expect(controller.isShuffled)
        #expect(controller.current != nil)
        #expect(controller.queue.items.count == tracks.count)
        #expect(Set(controller.queue.items.map(\.relativePath)) == Set(tracks.map(\.relativePath)))
        controller.stop()
    }

    @Test func nextAtTailUnderRepeatOffKeepsCurrentTrackUnchanged() {
        let controller = PlayerController()
        let only = makeTrack(duration: 10)
        controller.play([only])
        #expect(controller.current == only)
        let wasPlaying = controller.isPlaying

        controller.next()

        #expect(controller.current == only)
        #expect(controller.isPlaying == wasPlaying)
        controller.stop()
    }

    /// The batch `playNext(_ tracks:)` insert-reversed trick (each track
    /// individually inserted right after the current item, back-to-front)
    /// must leave the *visible* selection order intact ahead of whatever was
    /// already queued — not reversed.
    @Test func batchPlayNextPreservesOrderRightAfterCurrentTrack() {
        let controller = PlayerController()
        let current = makeTrack(relativePath: "current", duration: 10)
        controller.play([current])

        let a = makeTrack(relativePath: "a", duration: 10)
        let b = makeTrack(relativePath: "b", duration: 10)
        let c = makeTrack(relativePath: "c", duration: 10)
        controller.playNext([a, b, c])

        #expect(controller.queue.items.map(\.relativePath) == ["current", "a", "b", "c"])
        #expect(controller.current == current)
        controller.stop()
    }

    /// Batch `append(_ tracks:)` adds to the tail in order.
    @Test func batchAppendPreservesOrderAtTheTail() {
        let controller = PlayerController()
        let current = makeTrack(relativePath: "current", duration: 10)
        controller.play([current])

        let a = makeTrack(relativePath: "a", duration: 10)
        let b = makeTrack(relativePath: "b", duration: 10)
        controller.append([a, b])

        #expect(controller.queue.items.map(\.relativePath) == ["current", "a", "b"])
        #expect(controller.current == current)
        controller.stop()
    }
}

// MARK: - Test helpers

/// A fixed, non-real-time-derived track. The underlying file needs to exist
/// so `AVPlayerItem`/`AVQueuePlayer` construction is well-formed, but none of
/// these tests wait for decode to complete or rely on real playback timing.
private func makeTrack(relativePath: String = "controller-unit-test", duration: TimeInterval) -> PlayableTrack {
    PlayableTrack(
        relativePath: relativePath,
        url: TestFixtures.url("cbr-tagged.mp3"),
        title: relativePath,
        artist: "Artist",
        album: "Album",
        duration: duration,
        artworkID: nil
    )
}
