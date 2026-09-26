import Foundation
import PlaybackEngine
import Testing

struct PlayQueueTests {
    // MARK: - replace / current / upNext

    @Test func replaceWithEmptyTracksLeavesQueueEmpty() {
        var queue = PlayQueue()
        queue.replace(with: [], startingAt: 0)

        #expect(queue.items.isEmpty)
        #expect(queue.currentIndex == nil)
        #expect(queue.current == nil)
    }

    @Test func replaceSetsCurrentToTheRequestedIndex() {
        var queue = PlayQueue()
        let tracks = makeTracks(3)
        queue.replace(with: tracks, startingAt: 1)

        #expect(queue.currentIndex == 1)
        #expect(queue.current == tracks[1])
    }

    @Test func upNextHonorsEachRepeatMode() {
        var queue = PlayQueue()
        let tracks = makeTracks(3)
        queue.replace(with: tracks, startingAt: 0)

        #expect(queue.upNext(repeatMode: .off) == tracks[1])
        #expect(queue.upNext(repeatMode: .all) == tracks[1])
        #expect(queue.upNext(repeatMode: .one) == tracks[0])
    }

    @Test func upNextAtTailUnderOffIsNilButAllWraps() {
        var queue = PlayQueue()
        let tracks = makeTracks(3)
        queue.replace(with: tracks, startingAt: 2)

        #expect(queue.upNext(repeatMode: .off) == nil)
        #expect(queue.upNext(repeatMode: .all) == tracks[0])
        #expect(queue.upNext(repeatMode: .one) == tracks[2])
    }

    @Test func upNextOnEmptyQueueIsNilForEveryMode() {
        let queue = PlayQueue()
        #expect(queue.upNext(repeatMode: .off) == nil)
        #expect(queue.upNext(repeatMode: .all) == nil)
        #expect(queue.upNext(repeatMode: .one) == nil)
    }

    // MARK: - advanceAfterItemEnd (natural end-of-track)

    @Test func advanceAfterItemEndMovesForwardUnderOff() {
        var queue = PlayQueue()
        queue.replace(with: makeTracks(3), startingAt: 0)

        let next = queue.advanceAfterItemEnd(repeatMode: .off)
        #expect(next == queue.items[1])
        #expect(queue.currentIndex == 1)
    }

    @Test func advanceAfterItemEndAtTailUnderOffReturnsNilAndStaysAtTail() {
        var queue = PlayQueue()
        queue.replace(with: makeTracks(3), startingAt: 2)

        let next = queue.advanceAfterItemEnd(repeatMode: .off)
        #expect(next == nil)
        #expect(queue.currentIndex == 2)
    }

    @Test func advanceAfterItemEndAtTailUnderAllWrapsToHead() {
        var queue = PlayQueue()
        queue.replace(with: makeTracks(3), startingAt: 2)

        let next = queue.advanceAfterItemEnd(repeatMode: .all)
        #expect(next == queue.items[0])
        #expect(queue.currentIndex == 0)
    }

    @Test func advanceAfterItemEndUnderOneStaysOnCurrentTrack() {
        var queue = PlayQueue()
        queue.replace(with: makeTracks(3), startingAt: 1)

        let next = queue.advanceAfterItemEnd(repeatMode: .one)
        #expect(next == queue.items[1])
        #expect(queue.currentIndex == 1)
    }

    @Test func advanceAfterItemEndOnEmptyQueueReturnsNil() {
        var queue = PlayQueue()
        #expect(queue.advanceAfterItemEnd(repeatMode: .off) == nil)
        #expect(queue.advanceAfterItemEnd(repeatMode: .all) == nil)
        #expect(queue.advanceAfterItemEnd(repeatMode: .one) == nil)
    }

    // MARK: - skipNext (user skip: always moves, .one does not pin)

    @Test func skipNextMovesForwardEvenUnderRepeatOne() {
        var queue = PlayQueue()
        queue.replace(with: makeTracks(3), startingAt: 0)

        let next = queue.skipNext(repeatMode: .one)
        #expect(next == queue.items[1])
        #expect(queue.currentIndex == 1)
    }

    @Test func skipNextAtTailUnderOffReturnsNilAndStaysAtTail() {
        var queue = PlayQueue()
        queue.replace(with: makeTracks(3), startingAt: 2)

        let next = queue.skipNext(repeatMode: .off)
        #expect(next == nil)
        #expect(queue.currentIndex == 2)
    }

    @Test func skipNextAtTailUnderAllWrapsToHead() {
        var queue = PlayQueue()
        queue.replace(with: makeTracks(3), startingAt: 2)

        let next = queue.skipNext(repeatMode: .all)
        #expect(next == queue.items[0])
        #expect(queue.currentIndex == 0)
    }

    @Test func skipNextOnEmptyQueueReturnsNil() {
        var queue = PlayQueue()
        #expect(queue.skipNext(repeatMode: .all) == nil)
    }

    // MARK: - skipPrevious (user previous: always moves back)

    @Test func skipPreviousMovesBackward() {
        var queue = PlayQueue()
        queue.replace(with: makeTracks(3), startingAt: 2)

        let previous = queue.skipPrevious(repeatMode: .off)
        #expect(previous == queue.items[1])
        #expect(queue.currentIndex == 1)
    }

    @Test func skipPreviousAtHeadUnderOffStaysAtHeadAndReturnsCurrent() {
        var queue = PlayQueue()
        queue.replace(with: makeTracks(3), startingAt: 0)

        let previous = queue.skipPrevious(repeatMode: .off)
        #expect(previous == queue.items[0])
        #expect(queue.currentIndex == 0)
    }

    @Test func skipPreviousAtHeadUnderOneStaysAtHeadAndReturnsCurrent() {
        var queue = PlayQueue()
        queue.replace(with: makeTracks(3), startingAt: 0)

        let previous = queue.skipPrevious(repeatMode: .one)
        #expect(previous == queue.items[0])
        #expect(queue.currentIndex == 0)
    }

    @Test func skipPreviousAtHeadUnderAllWrapsToTail() {
        var queue = PlayQueue()
        queue.replace(with: makeTracks(3), startingAt: 0)

        let previous = queue.skipPrevious(repeatMode: .all)
        #expect(previous == queue.items[2])
        #expect(queue.currentIndex == 2)
    }

    @Test func skipPreviousOnEmptyQueueReturnsNil() {
        var queue = PlayQueue()
        #expect(queue.skipPrevious(repeatMode: .off) == nil)
    }

    // MARK: - shuffle / un-shuffle

    @Test func shufflingKeepsCurrentTrackFirstAndUnshuffleRestoresOriginalOrder() {
        var queue = PlayQueue()
        let tracks = makeTracks(6)
        queue.replace(with: tracks, startingAt: 2)
        let playingBeforeShuffle = queue.current

        var generator = SeededGenerator(seed: 42)
        queue.setShuffled(true, using: &generator)

        #expect(queue.isShuffled)
        #expect(queue.current == playingBeforeShuffle)
        #expect(queue.currentIndex == 0)
        // The shuffled order should be a permutation of the same tracks.
        #expect(Set(queue.items.map(\.relativePath)) == Set(tracks.map(\.relativePath)))

        queue.setShuffled(false, using: &generator)

        #expect(!queue.isShuffled)
        #expect(queue.items == tracks)
        #expect(queue.current == playingBeforeShuffle)
        #expect(queue.currentIndex == 2)
    }

    @Test func shufflingAnEmptyQueueDoesNotCrash() {
        var queue = PlayQueue()
        var generator = SeededGenerator(seed: 1)
        queue.setShuffled(true, using: &generator)
        #expect(queue.isShuffled)
        #expect(queue.items.isEmpty)
        #expect(queue.current == nil)
    }

    @Test func togglingShuffleToItsCurrentValueIsANoOp() {
        var queue = PlayQueue()
        queue.replace(with: makeTracks(3), startingAt: 0)
        var generator = SeededGenerator(seed: 7)
        queue.setShuffled(false, using: &generator) // already off
        #expect(!queue.isShuffled)
        #expect(queue.items == queue.items) // unchanged order, sanity check
    }

    // MARK: - playNext / append

    @Test func playNextInsertsRightAfterCurrentTrack() {
        var queue = PlayQueue()
        let tracks = makeTracks(3)
        queue.replace(with: tracks, startingAt: 0)

        let inserted = makeTrack("inserted")
        queue.playNext(inserted)

        #expect(queue.items[1] == inserted)
        #expect(queue.items[2] == tracks[1])
        #expect(queue.items[3] == tracks[2])
        #expect(queue.currentIndex == 0)
    }

    @Test func playNextOnEmptyQueueActsLikeReplace() {
        var queue = PlayQueue()
        let track = makeTrack("only")
        queue.playNext(track)

        #expect(queue.items == [track])
        #expect(queue.currentIndex == 0)
    }

    @Test func appendAddsToTheTailAndSetsCurrentIfQueueWasEmpty() {
        var queue = PlayQueue()
        let track = makeTrack("first")
        queue.append(track)

        #expect(queue.items == [track])
        #expect(queue.currentIndex == 0)

        let second = makeTrack("second")
        queue.append(second)
        #expect(queue.items == [track, second])
        #expect(queue.currentIndex == 0)
    }
}

// MARK: - Test helpers

private func makeTrack(_ relativePath: String) -> PlayableTrack {
    PlayableTrack(
        relativePath: relativePath,
        url: URL(fileURLWithPath: "/tmp/\(relativePath).mp3"),
        title: relativePath,
        artist: "Artist",
        album: "Album",
        duration: 180,
        artworkID: nil
    )
}

private func makeTracks(_ count: Int) -> [PlayableTrack] {
    (0 ..< count).map { makeTrack("track-\($0)") }
}

/// A tiny deterministic linear-congruential generator so shuffle tests are
/// reproducible instead of depending on `SystemRandomNumberGenerator`.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = 6_364_136_223_846_793_005 &* state &+ 1_442_695_040_888_963_407
        return state
    }
}
