import AVFoundation
import Foundation
import Observation
import os

/// Owns an `AVQueuePlayer` and the app-level `PlayQueue` (shuffle/repeat,
/// play-next, etc). The player itself only ever holds at most two items —
/// the currently playing one and whatever should preload next — the queue
/// is the single source of truth for play order.
@MainActor
@Observable
public final class PlayerController {
    public private(set) var queue = PlayQueue()
    public private(set) var isPlaying = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var repeatMode: RepeatMode = .off

    public var current: PlayableTrack? {
        queue.current
    }

    public var isShuffled: Bool {
        queue.isShuffled
    }

    private let player = AVQueuePlayer()
    // These three are bookkeeping only (never rendered), so they're excluded
    // from observation tracking. They're only ever written from the main
    // actor, and only ever read cross-isolation once, from `deinit`, after
    // which no other access can occur — `nonisolated(unsafe)` documents that
    // in place of `@unchecked Sendable` on the whole type.
    @ObservationIgnored private nonisolated(unsafe) var timeObserverToken: Any?
    @ObservationIgnored private nonisolated(unsafe) var endOfItemObserver: NSObjectProtocol?
    @ObservationIgnored private nonisolated(unsafe) var failureObserver: NSObjectProtocol?

    /// Which `relativePath` each currently-enqueued `AVPlayerItem` represents,
    /// so the end-of-item notification can be verified against, and the new
    /// current track can be checked against, the queue's own state.
    private var itemTracks: [ObjectIdentifier: String] = [:]

    #if os(iOS)
        private let audioSession = AudioSessionCoordinator()
    #endif

    private static let logger = Logger(subsystem: "OldPodKit.PlaybackEngine", category: "PlayerController")

    public init() {
        player.actionAtItemEnd = .advance

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds
            }
        }

        failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let failedItemID = (notification.object as? AVPlayerItem).map(ObjectIdentifier.init)
            Task { @MainActor in
                self?.handleItemFailure(failedItemID)
            }
        }

        #if os(iOS)
            audioSession.onPauseRequested = { [weak self] in
                Task { @MainActor in
                    self?.handleExternalPause()
                }
            }
            audioSession.onResumeRequested = { [weak self] in
                Task { @MainActor in
                    self?.handleExternalResume()
                }
            }
        #endif
    }

    deinit {
        let player = player
        let token = timeObserverToken
        if let token {
            player.removeTimeObserver(token)
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        if let endOfItemObserver {
            NotificationCenter.default.removeObserver(endOfItemObserver)
        }
    }

    public func play(_ tracks: [PlayableTrack], startingAt index: Int = 0) {
        queue.replace(with: tracks, startingAt: index)
        syncPlayerItems(fullRebuild: true)
        beginPlayback()
    }

    public func togglePlayPause() {
        guard queue.current != nil else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            beginPlayback()
        }
    }

    public func next() {
        guard queue.skipNext(repeatMode: repeatMode) != nil else { return }
        syncPlayerItems(fullRebuild: true)
        if isPlaying {
            beginPlayback()
        }
    }

    public func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard queue.skipPrevious(repeatMode: repeatMode) != nil else { return }
        syncPlayerItems(fullRebuild: true)
        if isPlaying {
            beginPlayback()
        }
    }

    public func seek(to seconds: TimeInterval) {
        guard let current = queue.current else { return }
        let clamped = max(0, min(seconds, current.duration))
        currentTime = clamped
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func toggleShuffle() {
        var generator = SystemRandomNumberGenerator()
        queue.setShuffled(!queue.isShuffled, using: &generator)
        syncPlayerItems(fullRebuild: true)
    }

    public func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        syncPlayerItems(fullRebuild: false)
    }

    public func playNext(_ track: PlayableTrack) {
        let hadCurrent = queue.current != nil
        queue.playNext(track)
        syncPlayerItems(fullRebuild: !hadCurrent)
    }

    public func append(_ track: PlayableTrack) {
        let hadCurrent = queue.current != nil
        queue.append(track)
        if !hadCurrent {
            syncPlayerItems(fullRebuild: true)
        } else {
            syncPlayerItems(fullRebuild: false)
        }
    }

    public func stop() {
        player.pause()
        isPlaying = false
        player.seek(to: .zero)
        currentTime = 0
    }

    // MARK: - Player item management

    private func beginPlayback() {
        guard queue.current != nil else { return }
        #if os(iOS)
            audioSession.ensureActive()
        #endif
        player.play()
        isPlaying = true
    }

    /// Rebuilds the player's item list from the queue. `fullRebuild` clears
    /// everything (used when the *current* item changed); otherwise only the
    /// tail (the preloaded "next" item) is replaced, so a currently-playing
    /// item is never interrupted just because `upNext` changed (e.g. a
    /// repeat-mode toggle).
    private func syncPlayerItems(fullRebuild: Bool) {
        guard let current = queue.current else {
            removeEndOfItemObserver()
            player.removeAllItems()
            itemTracks.removeAll()
            return
        }

        if fullRebuild {
            player.removeAllItems()
            itemTracks.removeAll()
            let currentItem = makeItem(for: current)
            player.insert(currentItem, after: nil)
            observeEndOfItem(currentItem)
        } else {
            // Keep the currently playing item; only touch what comes after it.
            let items = player.items()
            if let head = items.first {
                for tail in items.dropFirst() {
                    player.remove(tail)
                    itemTracks.removeValue(forKey: ObjectIdentifier(tail))
                }
                observeEndOfItem(head)
            } else {
                let currentItem = makeItem(for: current)
                player.insert(currentItem, after: nil)
                observeEndOfItem(currentItem)
            }
        }

        if let upNext = queue.upNext(repeatMode: repeatMode) {
            let nextItem = makeItem(for: upNext)
            player.insert(nextItem, after: player.items().first)
        }
    }

    private func makeItem(for track: PlayableTrack) -> AVPlayerItem {
        let item = AVPlayerItem(url: track.url)
        itemTracks[ObjectIdentifier(item)] = track.relativePath
        return item
    }

    private func observeEndOfItem(_ item: AVPlayerItem) {
        removeEndOfItemObserver()
        endOfItemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleItemDidEnd()
            }
        }
    }

    private func removeEndOfItemObserver() {
        if let endOfItemObserver {
            NotificationCenter.default.removeObserver(endOfItemObserver)
        }
        endOfItemObserver = nil
    }

    /// Invariant this relies on: `upNext(repeatMode: .one)` always preloads
    /// the *same* track as the one that just ended, so when `.actionAtItemEnd
    /// == .advance` moves the player into that preloaded duplicate item, we
    /// simply let it keep playing and re-arm the next preloaded duplicate —
    /// there's no seek-to-zero needed, and no visible gap. (The alternative
    /// of seeking the *same* item back to zero was considered, but that
    /// would fight the player's own auto-advance into the duplicate and
    /// require tearing down/re-adding items anyway.)
    private func handleItemDidEnd() {
        guard let track = queue.advanceAfterItemEnd(repeatMode: repeatMode) else {
            // .off at the tail: nothing more to play. The player has run out
            // of items, but the queue still points at the last track — re-arm
            // it paused at zero so a later play restarts it rather than
            // playing into an empty player.
            player.pause()
            isPlaying = false
            syncPlayerItems(fullRebuild: true)
            player.seek(to: .zero)
            currentTime = 0
            return
        }

        // The player already auto-advanced (`actionAtItemEnd == .advance`)
        // into the item that was preloaded as "next". Verify it actually
        // matches the queue's new current track; if not (e.g. the preload
        // hadn't caught up with a just-changed repeat mode), rebuild.
        // Prune mappings for items no longer held by the player (the item
        // that just ended, mainly) — ObjectIdentifiers of deallocated items
        // may be reused by future allocations, so stale entries must not
        // linger.
        let live = Set(player.items().map(ObjectIdentifier.init))
        itemTracks = itemTracks.filter { live.contains($0.key) }

        if let playingItem = player.currentItem,
           itemTracks[ObjectIdentifier(playingItem)] == track.relativePath
        {
            observeEndOfItem(playingItem)
            // Top up the tail with the next preload.
            if let upNext = queue.upNext(repeatMode: repeatMode) {
                let items = player.items()
                for tail in items.dropFirst() {
                    player.remove(tail)
                    itemTracks.removeValue(forKey: ObjectIdentifier(tail))
                }
                let nextItem = makeItem(for: upNext)
                player.insert(nextItem, after: playingItem)
            }
        } else {
            syncPlayerItems(fullRebuild: true)
            if isPlaying {
                beginPlayback()
            }
        }
    }

    private func handleItemFailure(_ failedItemID: ObjectIdentifier?) {
        guard let failedItemID, itemTracks[failedItemID] != nil else { return }
        Self.logger.error("AVPlayerItem failed to play to end; skipping to next track.")
        next()
    }

    #if os(iOS)
        private func handleExternalPause() {
            guard isPlaying else { return }
            player.pause()
            isPlaying = false
        }

        private func handleExternalResume() {
            guard queue.current != nil, !isPlaying else { return }
            beginPlayback()
        }
    #endif
}
