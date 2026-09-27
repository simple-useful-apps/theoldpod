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

    @Test func unplayableEmptyFileIsSkippedToTheNextQueuedTrack() async throws {
        let controller = PlayerController()
        let empty = try makeUnplayableTrack(named: "empty.mp3", contents: Data())
        let cbr = try await makePlayableTrack(fixture: "cbr-tagged.mp3")

        controller.play([empty, cbr])

        try await poll(timeout: .seconds(3)) { controller.current == cbr }

        #expect(controller.isPlaying)
        #expect(controller.current == cbr)

        controller.stop()
    }

    @Test func corruptRandomBytesFileIsSkippedToTheNextQueuedTrack() async throws {
        let controller = PlayerController()
        let corrupt = try makeUnplayableTrack(named: "corrupt.mp3", contents: randomBytes(count: 50000))
        let cbr = try await makePlayableTrack(fixture: "cbr-tagged.mp3")

        controller.play([corrupt, cbr])

        try await poll(timeout: .seconds(3)) { controller.current == cbr }

        #expect(controller.isPlaying)
        #expect(controller.current == cbr)

        controller.stop()
    }

    /// When the unplayable track is the last (only) one in the queue, there's
    /// nothing to skip to. Playback should stop cleanly rather than leaving
    /// `isPlaying` stuck `true` forever over a track that will never play.
    @Test func unplayableTrackAtEndOfQueueStopsPlaybackCleanly() async throws {
        let controller = PlayerController()
        let empty = try makeUnplayableTrack(named: "empty.mp3", contents: Data())

        controller.play([empty])

        try await poll(timeout: .seconds(3)) { !controller.isPlaying }

        #expect(!controller.isPlaying)
        #expect(controller.current == empty)

        controller.stop()
    }

    @Test func skippingAnUnplayableFileShowsANoticeNamingIt() async throws {
        let controller = PlayerController()
        // A 0-byte file always fails. Random bytes occasionally contain
        // enough MP3 frame syncs to "play" as noise, which made this flaky.
        let empty = try makeUnplayableTrack(named: "empty.mp3", contents: Data())
        let cbr = try await makePlayableTrack(fixture: "cbr-tagged.mp3")
        #expect(controller.unplayableNotice == nil)

        controller.play([empty, cbr])

        try await poll(timeout: .seconds(3)) { controller.current == cbr }
        #expect(controller.unplayableNotice == "Couldn’t play “empty.mp3”.")

        // Starting something else on purpose clears it straight away.
        controller.play([cbr])
        #expect(controller.unplayableNotice == nil)

        controller.stop()
    }

    @Test func stoppingOnAnUnplayableLastFileShowsANotice() async throws {
        let controller = PlayerController()
        let empty = try makeUnplayableTrack(named: "empty.mp3", contents: Data())

        controller.play([empty])

        try await poll(timeout: .seconds(3)) { !controller.isPlaying }
        #expect(controller.unplayableNotice == "Couldn’t play “empty.mp3”.")

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

/// Writes `contents` to a fresh temp-directory file named `name` and wraps it
/// as a `PlayableTrack` — used to reproduce unplayable files (empty, or
/// garbage bytes) without adding anything to `Fixtures/`.
private func makeUnplayableTrack(named name: String, contents: Data) throws -> PlayableTrack {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try contents.write(to: url)
    return PlayableTrack(
        relativePath: name,
        url: url,
        title: name,
        artist: "Artist",
        album: "Album",
        duration: 0,
        artworkID: nil
    )
}

private func randomBytes(count: Int) -> Data {
    var data = Data(count: count)
    data.withUnsafeMutableBytes { buffer in
        for i in 0 ..< buffer.count {
            buffer[i] = UInt8.random(in: .min ... .max)
        }
    }
    return data
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
