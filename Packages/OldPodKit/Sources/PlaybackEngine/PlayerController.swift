import AVFoundation
import CloudFiles
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
    public private(set) var currentDuration: TimeInterval = 0
    public private(set) var canSeek = false
    public private(set) var repeatMode: RepeatMode = .off
    public private(set) var playbackSpeed: Float = 1
    public static let supportedSpeeds: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2]
    public private(set) var playbackNotice: String?
    /// Bumped on every explicit seek, so observers can react to position
    /// discontinuities without observing `currentTime`'s half-second ticks.
    public private(set) var seekCount = 0

    private let history: ListeningHistory
    private var pendingSeek: PendingSeek?
    private var seekGeneration = 0
    /// `currentTime` came from the player rather than from a request that
    /// may not have landed yet.
    private var hasAuthoritativeCurrentTime = false
    private var hasRestored = false
    private var bookFinished = false
    private var resumeAfterInterruption = false

    public var current: PlayableTrack? {
        queue.current
    }

    public var isShuffled: Bool {
        queue.isShuffled
    }

    public var progressSaveFailed: Bool {
        history.saveFailed
    }

    private let player = AVQueuePlayer()
    // Observation bookkeeping: written on the main actor, read once more
    // from `deinit`, and never rendered.
    @ObservationIgnored private nonisolated(unsafe) var timeObserverToken: Any?
    @ObservationIgnored private nonisolated(unsafe) var endOfItemObserver: NSObjectProtocol?
    @ObservationIgnored private nonisolated(unsafe) var failureObserver: NSObjectProtocol?
    @ObservationIgnored private nonisolated(unsafe) var itemStatusObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]

    /// Which `relativePath` each enqueued `AVPlayerItem` represents, so item
    /// notifications can be checked against the queue's own state.
    private var itemTracks: [ObjectIdentifier: String] = [:]

    private let audioSession = AudioSessionCoordinator()

    private static let logger = Logger(subsystem: "OldPodKit.PlaybackEngine", category: "PlayerController")

    /// A seek the player has been asked for but has not confirmed. The
    /// player only honours seeks on a ready item, so a request may wait for
    /// the item, be retried, or be dropped when the item changes.
    private struct PendingSeek {
        let target: TimeInterval
        let itemID: ObjectIdentifier?
        let generation: Int
        var retries = 0
        var isInFlight = false
    }

    public init(historyURL: URL? = nil) {
        history = ListeningHistory(url: historyURL)
        player.actionAtItemEnd = .advance

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handleTimeTick()
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
        guard !tracks.isEmpty else { return }
        let target = tracks[tracks.indices.contains(index) ? index : 0]
        guard prepareForPlayback(target) else { return }
        saveProgress()
        bookFinished = false
        queue.replace(with: tracks, startingAt: index)
        playbackSpeed = current?.bookID.flatMap { history.bookmark(for: $0)?.speed } ?? 1
        if current?.bookID != nil { repeatMode = .off }
        syncPlayerItems(fullRebuild: true)
        beginPlayback()
        saveProgress()
    }

    /// Plays the tracks shuffled, starting from a random track, as every
    /// Shuffle button expects. (`play` then `toggleShuffle` would always
    /// start on the first track, because shuffling pins the current track.)
    public func playShuffled(_ tracks: [PlayableTrack]) {
        guard !tracks.isEmpty else { return }
        saveProgress()
        bookFinished = false
        playbackSpeed = 1
        queue.replace(with: tracks, startingAt: Int.random(in: tracks.indices))
        var generator = SystemRandomNumberGenerator()
        queue.setShuffled(true, using: &generator)
        syncPlayerItems(fullRebuild: true)
        beginPlayback()
        saveProgress()
    }

    public func togglePlayPause() {
        guard queue.current != nil else { return }
        if isPlaying {
            pause()
            saveProgress()
        } else {
            if player.currentItem?.status == .failed {
                let retryTime = currentTime
                syncPlayerItems(fullRebuild: true)
                if retryTime > 0 { seek(to: retryTime) }
            } else if let seek = pendingSeek, !seek.isInFlight {
                pendingSeek?.retries = 0
                performPendingSeek()
            }
            beginPlayback()
        }
    }

    public func next() {
        saveProgress()
        guard queue.skipNext(repeatMode: repeatMode) != nil else { return }
        bookFinished = false
        syncPlayerItems(fullRebuild: true)
        if isPlaying {
            beginPlayback()
        }
        saveProgress()
    }

    public func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        saveProgress()
        guard queue.skipPrevious(repeatMode: repeatMode) != nil else { return }
        bookFinished = false
        syncPlayerItems(fullRebuild: true)
        if isPlaying {
            beginPlayback()
        }
        saveProgress()
    }

    public func seek(to seconds: TimeInterval) {
        guard queue.current != nil, seconds.isFinite else { return }
        let clamped = currentDuration > 0 ? max(0, min(seconds, currentDuration)) : max(0, seconds)
        currentTime = clamped
        hasAuthoritativeCurrentTime = false
        seekCount += 1
        bookFinished = false
        seekGeneration += 1
        pendingSeek = PendingSeek(
            target: clamped,
            itemID: player.currentItem.map(ObjectIdentifier.init),
            generation: seekGeneration
        )
        performPendingSeek()
    }

    private func performPendingSeek() {
        guard canSeek, var seek = pendingSeek, !seek.isInFlight,
              let item = player.currentItem, seek.itemID == ObjectIdentifier(item) else { return }
        let itemID = ObjectIdentifier(item)
        let generation = seek.generation
        let target = currentDuration > 0 ? min(seek.target, currentDuration) : seek.target
        currentTime = target
        seek.isInFlight = true
        pendingSeek = seek
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
                self.handleSeekResult(finished: finished, generation: generation, itemID: itemID)
            }
        }
    }

    private func handleSeekResult(finished: Bool, generation: Int, itemID: ObjectIdentifier) {
        guard var seek = pendingSeek, seek.generation == generation,
              player.currentItem.map(ObjectIdentifier.init) == itemID else { return }
        seek.isInFlight = false
        guard finished else {
            guard seek.retries < 3 else {
                pendingSeek = seek
                pause()
                playbackNotice = "The chapter couldn’t move to that position. Adjust the slider or press Play to try again. Your saved position is unchanged."
                return
            }
            seek.retries += 1
            pendingSeek = seek
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, pendingSeek?.generation == generation else { return }
                performPendingSeek()
            }
            return
        }
        pendingSeek = nil
        hasAuthoritativeCurrentTime = true
        saveProgress()
    }

    public func skip(by seconds: TimeInterval) {
        let itemTime = player.currentItem?.currentTime().seconds
        let actual = itemTime?.isFinite == true ? itemTime! : currentTime
        seek(to: (pendingSeek?.target ?? actual) + seconds)
    }

    public func setSpeed(_ speed: Float) {
        guard Self.supportedSpeeds.contains(speed) else { return }
        playbackSpeed = speed
        if isPlaying { player.rate = speed }
        saveProgress()
    }

    /// Resume this book even after listening to something else. Selecting a
    /// chapter explicitly still starts that chapter at zero.
    public func resumeBook(_ tracks: [PlayableTrack]) {
        guard let bookID = tracks.first?.bookID else { return }
        saveProgress()
        let bookmark = history.bookmark(for: bookID)
        let index = bookmark.flatMap { mark in tracks.firstIndex { $0.relativePath == mark.path } } ?? 0
        guard prepareForPlayback(tracks[bookmark?.finished == true ? 0 : index]) else { return }
        play(tracks, startingAt: bookmark?.finished == true ? 0 : index)
        if let bookmark, !bookmark.finished,
           current?.relativePath == bookmark.path { seek(to: bookmark.seconds) }
    }

    public func bookProgress(_ bookID: String) -> (path: String, seconds: Double, finished: Bool)? {
        guard let mark = history.bookmark(for: bookID) else { return nil }
        return (mark.path, mark.seconds, mark.finished)
    }

    /// Called after the first index snapshot. Re-resolve URLs from the current
    /// root and omit missing tracks; never start audio on launch.
    public func restoreSession(available: [PlayableTrack]) {
        guard !hasRestored else { return }
        guard current == nil, let session = history.session else {
            hasRestored = true
            return
        }
        guard session.paths.indices.contains(session.index) else { return }
        let byPath = Dictionary(available.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        let remaining = session.paths.enumerated().compactMap { index, path in byPath[path].map { (index, $0) } }
        guard !remaining.isEmpty else { return }
        let restoredIndex = remaining.firstIndex { $0.0 == session.index } ?? 0
        // Wait for cloud metadata/download instead of clamping a saved
        // position to zero against a temporary zero-duration placeholder.
        guard remaining[restoredIndex].1.isDownloaded else { return }
        hasRestored = true
        let wasFinished = remaining[restoredIndex].1.bookID.flatMap { history.bookmark(for: $0)?.finished } ?? false
        queue.replace(with: remaining.map(\.1), startingAt: restoredIndex)
        playbackSpeed = Self.supportedSpeeds.contains(session.speed) ? session.speed : 1
        syncPlayerItems(fullRebuild: true)
        if remaining[restoredIndex].0 == session.index { seek(to: session.seconds) }
        bookFinished = wasFinished
        saveProgress()
    }

    public func saveProgress() {
        if let current, let index = queue.currentIndex, currentTime.isFinite, hasAuthoritativeCurrentTime {
            history.record(
                session: .init(paths: queue.items.map(\.relativePath), index: index, seconds: currentTime, speed: playbackSpeed),
                bookmark: current.bookID.map {
                    ($0, .init(path: current.relativePath, seconds: currentTime, speed: playbackSpeed, finished: bookFinished))
                }
            )
        }
        history.save()
    }

    /// Reconciles the in-memory queue and device-local resume history after
    /// files have actually reached Trash. Removing a queued item never
    /// interrupts a surviving current item; removing the current item parks
    /// on the nearest survivor, paused at its beginning.
    public func removeDeletedLibraryItems(relativePaths: Set<String>, bookIDs: Set<String> = []) {
        guard !relativePaths.isEmpty || !bookIDs.isEmpty else { return }
        saveProgress()
        let outcome = queue.remove(relativePaths: relativePaths, bookIDs: bookIDs)
        history.forget(paths: relativePaths, bookIDs: bookIDs)

        switch outcome {
        case .unchanged:
            break
        case .currentPreserved:
            syncPlayerItems(fullRebuild: false)
        case .currentReplaced, .emptied:
            pause()
            bookFinished = false
            playbackNotice = nil
            playbackSpeed = current?.bookID.flatMap { history.bookmark(for: $0)?.speed } ?? 1
            syncPlayerItems(fullRebuild: true)
        }

        saveProgress()
    }

    private func prepareForPlayback(_ track: PlayableTrack) -> Bool {
        guard track.isDownloaded else {
            DownloadRequester.requestDownload(of: track.url)
            playbackNotice = "This file is downloading. Try again when it is available. Your saved position is unchanged."
            return false
        }
        playbackNotice = nil
        return true
    }

    public func toggleShuffle() {
        var generator = SystemRandomNumberGenerator()
        queue.setShuffled(!queue.isShuffled, using: &generator)
        syncPlayerItems(fullRebuild: false)
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
        playNext([track])
    }

    public func append(_ track: PlayableTrack) {
        append([track])
    }

    /// Inserts every track right after the current one, preserving order.
    /// Each track goes directly after the current item, so inserting the
    /// batch back-to-front leaves it in its original order.
    public func playNext(_ tracks: [PlayableTrack]) {
        guard !tracks.isEmpty else { return }
        let hadCurrent = queue.current != nil
        if hadCurrent {
            for track in tracks.reversed() {
                queue.playNext(track)
            }
        } else {
            queue.replace(with: tracks, startingAt: 0)
        }
        syncPlayerItems(fullRebuild: !hadCurrent)
        saveProgress()
    }

    /// Appends every track to the tail of the queue, in order.
    public func append(_ tracks: [PlayableTrack]) {
        guard !tracks.isEmpty else { return }
        let hadCurrent = queue.current != nil
        for track in tracks {
            queue.append(track)
        }
        syncPlayerItems(fullRebuild: !hadCurrent)
        saveProgress()
    }

    /// Pauses and rewinds. Pause is the app's idle state; tests use this to
    /// silence a controller at teardown.
    public func stop() {
        pause()
        player.seek(to: .zero)
        currentTime = 0
        saveProgress()
    }

    // MARK: - Player item management

    private func beginPlayback() {
        guard queue.current != nil else { return }
        audioSession.ensureActive()
        bookFinished = false
        resumeAfterInterruption = false
        player.playImmediately(atRate: playbackSpeed)
        isPlaying = true
    }

    private func pause() {
        player.pause()
        isPlaying = false
        resumeAfterInterruption = false
    }

    /// Forgets the position of the item being replaced. `duration` is the
    /// best known length of the new current track until the player reports it.
    private func resetPosition(duration: TimeInterval) {
        pendingSeek = nil
        currentTime = 0
        currentDuration = duration.isFinite ? max(duration, 0) : 0
        canSeek = false
        hasAuthoritativeCurrentTime = false
    }

    /// Rebuilds the player's item list from the queue. `fullRebuild` clears
    /// everything (used when the *current* item changed); otherwise only the
    /// tail (the preloaded "next" item) is replaced, so a currently-playing
    /// item is never interrupted just because `upNext` changed (e.g. a
    /// repeat-mode toggle).
    private func syncPlayerItems(fullRebuild: Bool) {
        guard let current = queue.current else {
            player.pause()
            isPlaying = false
            resetPosition(duration: 0)
            removeEndOfItemObserver()
            player.removeAllItems()
            itemTracks.removeAll()
            itemStatusObservations.removeAll()
            return
        }

        if fullRebuild {
            resetPosition(duration: current.duration)
            player.removeAllItems()
            itemTracks.removeAll()
            itemStatusObservations.removeAll()
            enqueueCurrent(current)
        } else if let head = player.items().first {
            // Keep the currently playing item; only touch what comes after it.
            removeTail(after: head)
            resolveDuration(for: head)
            observeEndOfItem(head)
        } else {
            enqueueCurrent(current)
        }

        if let upNext = queue.upNext(repeatMode: repeatMode) {
            let nextItem = makeItem(for: upNext)
            player.insert(nextItem, after: player.items().first)
            observeStatus(of: nextItem)
        }
    }

    private func enqueueCurrent(_ track: PlayableTrack) {
        let item = makeItem(for: track)
        player.insert(item, after: nil)
        observeStatus(of: item)
        resolveDuration(for: item)
        observeEndOfItem(item)
    }

    private func removeTail(after head: AVPlayerItem) {
        for tail in player.items() where tail !== head {
            player.remove(tail)
            itemTracks.removeValue(forKey: ObjectIdentifier(tail))
            itemStatusObservations.removeValue(forKey: ObjectIdentifier(tail))
        }
    }

    /// Every play path funnels through here, so an undownloaded iCloud file
    /// always gets its download started: the item fails and is skipped this
    /// time, and the bytes are there for the next attempt.
    private func makeItem(for track: PlayableTrack) -> AVPlayerItem {
        if !track.isDownloaded {
            DownloadRequester.requestDownload(of: track.url)
        }
        let item = AVPlayerItem(url: track.url)
        item.audioTimePitchAlgorithm = .timeDomain
        itemTracks[ObjectIdentifier(item)] = track.relativePath
        return item
    }

    private func resolveDuration(for item: AVPlayerItem) {
        let itemID = ObjectIdentifier(item)
        Task { [weak self, weak item] in
            guard let item else { return }
            let loaded = try? await item.asset.load(.duration, .isPlayable)
            guard let self, player.currentItem.map(ObjectIdentifier.init) == itemID,
                  item.status == .readyToPlay,
                  itemTracks[itemID] == current?.relativePath else { return }
            if let (duration, isPlayable) = loaded, isPlayable,
               duration.seconds.isFinite, duration.seconds > 0
            {
                currentDuration = duration.seconds
                canSeek = true
                playbackNotice = nil
                performPendingSeek()
            }
        }
    }

    private func observeStatus(of item: AVPlayerItem) {
        let itemID = ObjectIdentifier(item)
        itemStatusObservations[itemID] = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor in
                self?.handleItemStatus(status, itemID: itemID)
            }
        }
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status, itemID: ObjectIdentifier) {
        guard itemTracks[itemID] != nil else { return }
        switch status {
        case .readyToPlay:
            guard let item = player.currentItem, ObjectIdentifier(item) == itemID else { return }
            updateDurationIfAvailable(from: item)
            resolveDuration(for: item)
        case .failed:
            handleItemFailure(itemID)
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func updateDurationIfAvailable(from item: AVPlayerItem) {
        guard item.status == .readyToPlay else { return }
        let seconds = item.duration.seconds
        guard seconds.isFinite, seconds > 0 else { return }
        currentDuration = seconds
        canSeek = true
        performPendingSeek()
    }

    private func handleTimeTick() {
        guard pendingSeek == nil, let item = player.currentItem, item.status == .readyToPlay,
              itemTracks[ObjectIdentifier(item)] == current?.relativePath else { return }
        let seconds = item.currentTime().seconds
        guard seconds.isFinite else { return }
        updateDurationIfAvailable(from: item)
        currentTime = currentDuration > 0 ? max(0, min(seconds, currentDuration)) : max(0, seconds)
        hasAuthoritativeCurrentTime = true
        if isPlaying, Date().timeIntervalSince(history.lastSaved) >= 2 {
            saveProgress()
        }
    }

    public func refreshAvailableTracks(_ tracks: [PlayableTrack]) {
        queue.refreshMetadata(from: tracks)
        guard let current else { return }
        if current.duration > 0, current.duration.isFinite {
            currentDuration = max(currentDuration, current.duration)
            canSeek = player.currentItem?.status == .readyToPlay && current.isDownloaded
            performPendingSeek()
        }
    }

    private func observeEndOfItem(_ item: AVPlayerItem) {
        removeEndOfItemObserver()
        endOfItemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            let endedItemID = ObjectIdentifier(item)
            Task { @MainActor in
                guard self?.itemTracks[endedItemID] != nil else { return }
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

    /// The player has auto-advanced (`actionAtItemEnd == .advance`) into the
    /// preloaded item. Under repeat-one that preload is the same track again,
    /// so it simply keeps playing. If the preload does not match what the
    /// queue now says is current, rebuild.
    private func handleItemDidEnd() {
        pendingSeek = nil
        bookFinished = queue.upNext(repeatMode: repeatMode) == nil && current?.bookID != nil
        currentTime = currentDuration
        hasAuthoritativeCurrentTime = true
        saveProgress()
        resetPosition(duration: 0)
        guard let track = queue.advanceAfterItemEnd(repeatMode: repeatMode) else {
            // Repeat off at the tail: re-arm the last track paused at zero so
            // a later Play restarts it rather than playing into an empty player.
            player.pause()
            isPlaying = false
            syncPlayerItems(fullRebuild: true)
            player.seek(to: .zero)
            currentTime = 0
            saveProgress()
            return
        }

        // ObjectIdentifiers of freed items can be reused, so drop the mapping
        // for the item that just ended before trusting any lookup.
        let live = Set(player.items().map(ObjectIdentifier.init))
        itemTracks = itemTracks.filter { live.contains($0.key) }

        if let playingItem = player.currentItem,
           itemTracks[ObjectIdentifier(playingItem)] == track.relativePath
        {
            currentDuration = track.duration.isFinite ? max(track.duration, 0) : 0
            canSeek = currentDuration > 0
            updateDurationIfAvailable(from: playingItem)
            resolveDuration(for: playingItem)
            observeEndOfItem(playingItem)
            if let upNext = queue.upNext(repeatMode: repeatMode) {
                removeTail(after: playingItem)
                let nextItem = makeItem(for: upNext)
                player.insert(nextItem, after: playingItem)
                observeStatus(of: nextItem)
            }
        } else {
            syncPlayerItems(fullRebuild: true)
            if isPlaying {
                beginPlayback()
            }
        }
        if isPlaying { player.rate = playbackSpeed }
        saveProgress()
    }

    /// A preloaded item can fail while the current one plays fine (bad file,
    /// undownloaded iCloud placeholder). Only the playing item's failure
    /// skips; a failed preload is dropped and will be retried as current.
    ///
    /// `player.currentItem` cannot tell the two apart: with
    /// `actionAtItemEnd == .advance` the player discards a failed item and
    /// promotes the preload before this handler runs, so the failed item is
    /// matched against the queue's own `current` instead.
    private func handleItemFailure(_ failedItemID: ObjectIdentifier?) {
        guard let failedItemID, itemTracks[failedItemID] != nil else { return }
        if itemTracks[failedItemID] == current?.relativePath {
            if current?.bookID != nil {
                pause()
                pendingSeek = nil
                canSeek = false
                hasAuthoritativeCurrentTime = false
                playbackNotice = "This chapter couldn’t be played. Try again after it finishes downloading. Your saved position is unchanged."
                return
            }
            Self.logger.error("Playing item failed; skipping to next track.")
            guard queue.upNext(repeatMode: repeatMode) != nil else {
                // Nothing to skip to: stop cleanly rather than leaving
                // `isPlaying` set over a track that will never play.
                pause()
                syncPlayerItems(fullRebuild: true)
                player.seek(to: .zero)
                currentTime = 0
                saveProgress()
                return
            }
            next()
        } else {
            Self.logger.error("Preloaded item failed; removing it from the player.")
            for tail in player.items().dropFirst() where ObjectIdentifier(tail) == failedItemID {
                player.remove(tail)
            }
            itemTracks.removeValue(forKey: failedItemID)
            itemStatusObservations.removeValue(forKey: failedItemID)
        }
    }

    private func handleExternalPause() {
        resumeAfterInterruption = isPlaying
        guard isPlaying else { return }
        player.pause()
        isPlaying = false
        saveProgress()
    }

    private func handleExternalResume() {
        guard resumeAfterInterruption, queue.current != nil, !isPlaying else { return }
        beginPlayback()
    }
}
