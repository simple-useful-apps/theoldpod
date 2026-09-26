import Foundation
import PlaybackEngine
import Testing

/// Adversarial pass on `PlayQueue`, focused on shuffle/original-order
/// consistency, the `advanceAfterItemEnd` vs `skipNext`/`skipPrevious`
/// distinction on degenerate (single-item / empty / duplicate) queues, and
/// `Equatable` sanity. Complements `PlayQueueTests.swift`, which already
/// covers the straightforward per-mode happy paths.
struct PlayQueueEdgeCaseTests {
    // MARK: - Shuffle / original-order consistency

    @Test func playNextWhileShuffledKeepsInsertedTrackReachableAndCurrentUnchanged() {
        var queue = PlayQueue()
        let tracks = makeTracks(5)
        queue.replace(with: tracks, startingAt: 2)
        let playing = queue.current

        var generator = SeededGenerator(seed: 11)
        queue.setShuffled(true, using: &generator)
        #expect(queue.current == playing)

        let inserted = makeTrack("inserted-while-shuffled")
        queue.playNext(inserted)

        #expect(queue.current == playing)
        #expect(queue.items.count == 6)
        #expect(queue.items.contains(inserted))
        #expect(Set(queue.items.map(\.relativePath)) == Set(tracks.map(\.relativePath) + [inserted.relativePath]))
    }

    @Test func shuffleOffAfterPlayNextWhileShuffledPutsInsertedTrackAtTailOfRestoredOrder() {
        var queue = PlayQueue()
        let tracks = makeTracks(5)
        queue.replace(with: tracks, startingAt: 2)
        let playing = queue.current

        var generator = SeededGenerator(seed: 11)
        queue.setShuffled(true, using: &generator)
        let inserted = makeTrack("inserted-while-shuffled")
        queue.playNext(inserted)

        queue.setShuffled(false, using: &generator)

        // Documented rule: tracks inserted while shuffled are appended to the
        // tail of `originalOrder`, regardless of where they landed in the
        // shuffled `items`. So un-shuffling puts the inserted track last.
        #expect(queue.items == tracks + [inserted])
        #expect(queue.current == playing)
        #expect(!queue.isShuffled)
    }

    @Test func appendWhileShuffledSurvivesUnshuffleAtTail() {
        var queue = PlayQueue()
        let tracks = makeTracks(4)
        queue.replace(with: tracks, startingAt: 1)
        let playing = queue.current

        var generator = SeededGenerator(seed: 99)
        queue.setShuffled(true, using: &generator)
        let appended = makeTrack("appended-while-shuffled")
        queue.append(appended)

        #expect(queue.items.contains(appended))
        #expect(queue.current == playing)

        queue.setShuffled(false, using: &generator)

        #expect(queue.items == tracks + [appended])
        #expect(queue.current == playing)
    }

    @Test func shuffleThenSkipSeveralThenUnshuffleKeepsCurrentIndexOnSameTrack() throws {
        var queue = PlayQueue()
        let tracks = makeTracks(5)
        queue.replace(with: tracks, startingAt: 0)

        var generator = SeededGenerator(seed: 3)
        queue.setShuffled(true, using: &generator)

        _ = queue.skipNext(repeatMode: .off)
        _ = queue.skipNext(repeatMode: .off)
        _ = queue.skipNext(repeatMode: .off)
        let playingWhileShuffled = try #require(queue.current)

        queue.setShuffled(false, using: &generator)

        #expect(queue.items == tracks)
        #expect(queue.current == playingWhileShuffled)
        #expect(queue.currentIndex == tracks.firstIndex(of: playingWhileShuffled))
    }

    @Test func doubleShuffleOnIsANoOpAndKeepsAllItems() {
        var queue = PlayQueue()
        queue.replace(with: makeTracks(6), startingAt: 0)

        var generatorA = SeededGenerator(seed: 5)
        queue.setShuffled(true, using: &generatorA)
        let itemsAfterFirstShuffle = queue.items

        // A second "on" while already on must be a no-op per the `guard on
        // != isShuffled else { return }` — a different generator/seed must
        // not perturb the order, and no items may be lost or duplicated.
        var generatorB = SeededGenerator(seed: 123_456)
        queue.setShuffled(true, using: &generatorB)

        #expect(queue.items == itemsAfterFirstShuffle)
        #expect(queue.items.count == 6)
        #expect(queue.isShuffled)
    }

    @Test func shuffleOnThenOffOnEmptyQueueDoesNotCrash() {
        var queue = PlayQueue()
        var generator = SeededGenerator(seed: 1)
        queue.setShuffled(true, using: &generator)
        queue.setShuffled(false, using: &generator)

        #expect(!queue.isShuffled)
        #expect(queue.items.isEmpty)
        #expect(queue.current == nil)
    }

    @Test func shuffleWithASingleItemLeavesCurrentStable() {
        var queue = PlayQueue()
        let tracks = makeTracks(1)
        queue.replace(with: tracks, startingAt: 0)

        var generator = SeededGenerator(seed: 2)
        queue.setShuffled(true, using: &generator)
        #expect(queue.items == tracks)
        #expect(queue.current == tracks[0])

        queue.setShuffled(false, using: &generator)
        #expect(queue.items == tracks)
        #expect(queue.current == tracks[0])
    }

    // MARK: - advanceAfterItemEnd / skipNext / skipPrevious on a single-track queue

    @Test func advanceAfterItemEndOnSingleTrackQueueUnderEachRepeatMode() {
        var one = PlayQueue()
        let track = makeTrack("solo")
        one.replace(with: [track], startingAt: 0)
        #expect(one.advanceAfterItemEnd(repeatMode: .one) == track)
        #expect(one.currentIndex == 0)

        var all = PlayQueue()
        all.replace(with: [track], startingAt: 0)
        #expect(all.advanceAfterItemEnd(repeatMode: .all) == track)
        #expect(all.currentIndex == 0)

        var off = PlayQueue()
        off.replace(with: [track], startingAt: 0)
        #expect(off.advanceAfterItemEnd(repeatMode: .off) == nil)
        #expect(off.currentIndex == 0)
        #expect(off.current == track)
    }

    @Test func skipNextOnSingleTrackQueueUnderEachRepeatMode() {
        var off = PlayQueue()
        let track = makeTrack("solo")
        off.replace(with: [track], startingAt: 0)
        #expect(off.skipNext(repeatMode: .off) == nil)
        #expect(off.currentIndex == 0)

        var one = PlayQueue()
        one.replace(with: [track], startingAt: 0)
        // There's nowhere to move forward to on a single-item queue, so even
        // though `.one` normally "does not pin", skipNext still reports nil
        // here (the implementation's `.one`/`.off` branch both return nil
        // once past the tail) rather than re-returning the same track.
        #expect(one.skipNext(repeatMode: .one) == nil)
        #expect(one.currentIndex == 0)

        var all = PlayQueue()
        all.replace(with: [track], startingAt: 0)
        #expect(all.skipNext(repeatMode: .all) == track)
        #expect(all.currentIndex == 0)
    }

    @Test func skipPreviousOnSingleTrackQueueUnderEachRepeatMode() {
        let track = makeTrack("solo")

        var off = PlayQueue()
        off.replace(with: [track], startingAt: 0)
        #expect(off.skipPrevious(repeatMode: .off) == track)
        #expect(off.currentIndex == 0)

        var one = PlayQueue()
        one.replace(with: [track], startingAt: 0)
        #expect(one.skipPrevious(repeatMode: .one) == track)
        #expect(one.currentIndex == 0)

        var all = PlayQueue()
        all.replace(with: [track], startingAt: 0)
        #expect(all.skipPrevious(repeatMode: .all) == track)
        #expect(all.currentIndex == 0)
    }

    // MARK: - upNext consistency after playNext

    @Test func upNextMatchesInsertedTrackAfterPlayNextForEveryModeExceptOne() {
        var queue = PlayQueue()
        let tracks = makeTracks(3)
        queue.replace(with: tracks, startingAt: 0)

        let inserted = makeTrack("up-next-check")
        queue.playNext(inserted)

        #expect(queue.upNext(repeatMode: .off) == inserted)
        #expect(queue.upNext(repeatMode: .all) == inserted)
        // `.one` always repeats the *current* track, irrespective of anything
        // queued after it.
        #expect(queue.upNext(repeatMode: .one) == queue.current)
        #expect(queue.upNext(repeatMode: .one) == tracks[0])
    }

    // MARK: - Degenerate inputs

    @Test func replaceWithEmptyArrayMakesEveryOperationASafeNoOp() {
        var queue = PlayQueue()
        queue.replace(with: makeTracks(4), startingAt: 2) // start non-empty
        queue.replace(with: [], startingAt: 0)

        #expect(queue.current == nil)
        #expect(queue.currentIndex == nil)
        #expect(queue.items.isEmpty)

        for mode in RepeatMode.allCases {
            #expect(queue.upNext(repeatMode: mode) == nil)
            #expect(queue.advanceAfterItemEnd(repeatMode: mode) == nil)
            #expect(queue.skipNext(repeatMode: mode) == nil)
            #expect(queue.skipPrevious(repeatMode: mode) == nil)
        }
        #expect(queue.jump(to: 0) == nil)
        #expect(queue.current == nil)
        #expect(queue.currentIndex == nil)
    }

    @Test func replaceStartingAtNegativeIndexClampsRatherThanCrashing() {
        var queue = PlayQueue()
        let tracks = makeTracks(3)
        queue.replace(with: tracks, startingAt: -1)

        // Documented current behavior: an out-of-range start index (whether
        // negative or beyond the end) clamps to the head of the queue rather
        // than producing `nil`.
        #expect(queue.currentIndex == 0)
        #expect(queue.current == tracks[0])
    }

    @Test func replaceStartingAtIndexBeyondCountClampsRatherThanCrashing() {
        var queue = PlayQueue()
        let tracks = makeTracks(3)
        queue.replace(with: tracks, startingAt: 99)

        #expect(queue.currentIndex == 0)
        #expect(queue.current == tracks[0])
    }

    @Test func jumpOnEmptyQueueReturnsNil() {
        var queue = PlayQueue()
        #expect(queue.jump(to: 0) == nil)
        #expect(queue.jump(to: -1) == nil)
        #expect(queue.current == nil)
    }

    @Test func duplicateTracksAreBothPlayableAndSkipNextWalksThroughEachOccurrence() {
        var queue = PlayQueue()
        let a = makeTrack("dup-a")
        let b = makeTrack("dup-b")
        queue.replace(with: [a, a, b], startingAt: 0)

        #expect(queue.skipNext(repeatMode: .off) == a) // index 0 -> 1, still "a"
        #expect(queue.currentIndex == 1)
        #expect(queue.skipNext(repeatMode: .off) == b) // index 1 -> 2
        #expect(queue.currentIndex == 2)
        #expect(queue.skipNext(repeatMode: .off) == nil) // tail under .off
        #expect(queue.currentIndex == 2)
    }

    @Test func duplicateTracksSurviveShuffleAsAMultiset() {
        var queue = PlayQueue()
        let a = makeTrack("dup-a")
        let b = makeTrack("dup-b")
        queue.replace(with: [a, a, b], startingAt: 0)

        var generator = SeededGenerator(seed: 77)
        queue.setShuffled(true, using: &generator)
        #expect(queue.items.count == 3)
        #expect(queue.items.count(where: { $0 == a }) == 2)
        #expect(queue.items.count(where: { $0 == b }) == 1)

        queue.setShuffled(false, using: &generator)
        #expect(queue.items == [a, a, b])
    }

    /// FINDING: when the queue holds two value-equal tracks (identical
    /// `PlayableTrack`, e.g. the same file queued twice), `setShuffled`
    /// restores `currentIndex` via `originalOrder.firstIndex(of:
    /// currentTrack)`. Because the two copies are indistinguishable under
    /// `Equatable`, un-shuffling always snaps `currentIndex` back to the
    /// *first* occurrence — even if the second occurrence was the one
    /// actually playing before shuffle-on. This is silent (no crash, no data
    /// loss) but it does mean playback position can jump to a different,
    /// value-identical instance in the queue. Locking in the actual behavior
    /// here rather than asserting it "should" preserve index 1.
    @Test func duplicateTracksShuffleRestoreCanSnapCurrentIndexToFirstOccurrence() {
        var queue = PlayQueue()
        let a = makeTrack("dup-a")
        let b = makeTrack("dup-b")
        queue.replace(with: [a, a, b], startingAt: 1) // "current" is the *second* a

        var generator = SeededGenerator(seed: 8)
        queue.setShuffled(true, using: &generator)
        queue.setShuffled(false, using: &generator)

        #expect(queue.items == [a, a, b])
        #expect(queue.current == a) // still value-equal to what was playing
        #expect(queue.currentIndex == 0) // but NOT the original index (1)
    }

    // MARK: - playNext chaining

    @Test func playNextCalledTwiceInsertsSecondTrackAheadOfTheFirst() {
        var queue = PlayQueue()
        queue.replace(with: makeTracks(1), startingAt: 0)
        let current = queue.current

        let first = makeTrack("play-next-first")
        let second = makeTrack("play-next-second")
        queue.playNext(first)
        queue.playNext(second)

        // FINDING (flagged, not necessarily wrong — "iTunes semantics"):
        // each `playNext` call inserts immediately after the current index,
        // so calling it twice in a row produces LIFO order: the *most
        // recently* queued "play next" track ends up playing sooner than the
        // one queued before it. Order ends up [current, second, first, ...]
        // rather than the FIFO [current, first, second, ...] a caller who
        // tapped "Play Next" on `first` then `second` might expect.
        #expect(queue.items[0] == current)
        #expect(queue.items[1] == second)
        #expect(queue.items[2] == first)
        #expect(queue.currentIndex == 0)
    }

    // MARK: - Equatable sanity

    @Test func identicalOperationSequencesProduceEqualQueues() {
        var generatorA = SeededGenerator(seed: 42)
        var generatorB = SeededGenerator(seed: 42)

        var queueA = PlayQueue()
        let tracks = makeTracks(4)
        queueA.replace(with: tracks, startingAt: 1)
        queueA.setShuffled(true, using: &generatorA)
        queueA.playNext(makeTrack("extra"))

        var queueB = PlayQueue()
        queueB.replace(with: tracks, startingAt: 1)
        queueB.setShuffled(true, using: &generatorB)
        queueB.playNext(makeTrack("extra"))

        #expect(queueA == queueB)
    }

    @Test func queuesWithSameVisibleStateButDifferentHistoryAreNotNecessarilyEqual() {
        // Same final `items`/`currentIndex`/`isShuffled`, but reached via
        // different histories, so the *private* `originalOrder` differs (it
        // has no public accessor, so this is only observable through `==`,
        // which is struct-synthesized over every stored property). Not a
        // bug — just a sharp edge worth locking in for anyone tempted to use
        // `==` as a dedup/cache key: two queues that look identical through
        // every public property can still compare unequal, and will restore
        // a *different* order once shuffle is turned off.
        var queueA = PlayQueue()
        let tracks = makeTracks(3)
        queueA.replace(with: tracks, startingAt: 0)
        let inserted = makeTrack("history-divergence")
        queueA.playNext(inserted) // originalOrder becomes [t0, t1, t2, inserted]

        var queueB = PlayQueue()
        // Same resulting `items`, reached by constructing that order
        // directly instead of via `playNext` — so `originalOrder` matches
        // `items` (`[t0, inserted, t1, t2]`) rather than the insertion order.
        queueB.replace(with: [tracks[0], inserted, tracks[1], tracks[2]], startingAt: 0)

        #expect(queueA.items == queueB.items)
        #expect(queueA.currentIndex == queueB.currentIndex)
        #expect(queueA.isShuffled == queueB.isShuffled)
        #expect(queueA != queueB)
    }
}

// MARK: - Test helpers

// Mirrors the private helpers in PlayQueueTests.swift; duplicated here
// because those are `private` to that file.

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
    (0 ..< count).map { makeTrack("edge-track-\($0)") }
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
