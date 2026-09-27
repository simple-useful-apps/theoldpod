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
    public private(set) var progressSaveFailed = false
    public private(set) var playbackNotice: String?
    private var history = ListeningHistory()
    private let historyURL: URL?
    private var lastSave = Date.distantPast
    private var pendingSeek = false
    private var pendingSeekTarget: TimeInterval?
    private var pendingSeekItemID: ObjectIdentifier?
    private var activeSeekGeneration: Int?
    private var pendingSeekRetryCount = 0
    private var seekGeneration = 0
    private var hasAuthoritativeCurrentTime = false
    private var hasRestored = false
    private var bookFinished = false
    private var resumeAfterInterruption = false
    /// Bumped on every explicit seek. Lets observers (NowPlayingBridge) react
    /// to playback-position DISCONTINUITIES without observing `currentTime`
    /// itself, whose 0.5s ticks would otherwise fire them continuously.
    public private(set) var seekCount = 0

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
    @ObservationIgnored private nonisolated(unsafe) var itemStatusObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]

    /// Which `relativePath` each currently-enqueued `AVPlayerItem` represents,
    /// so the end-of-item notification can be verified against, and the new
    /// current track can be checked against, the queue's own state.
    private var itemTracks: [ObjectIdentifier: String] = [:]

    private let audioSession = AudioSessionCoordinator()

    private static let logger = Logger(subsystem: "OldPodKit.PlaybackEngine", category: "PlayerController")

    public init(historyURL: URL? = nil) {
        self.historyURL = historyURL
        if let historyURL, let data = try? Data(contentsOf: historyURL),
           let saved = try? JSONDecoder().decode(ListeningHistory.self, from: data)
        {
            history = saved
        }
        player.actionAtItemEnd = .advance

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.pendingSeek, let item = self.player.currentItem,
                      item.status == .readyToPlay,
                      self.itemTracks[ObjectIdentifier(item)] == self.current?.relativePath else { return }
                let seconds = item.currentTime().seconds
                guard seconds.isFinite else { return }
                self.updateDurationIfAvailable(from: item)
                self.currentTime = self.currentDuration > 0
                    ? max(0, min(seconds, self.currentDuration))
                    : max(0, seconds)
                self.hasAuthoritativeCurrentTime = true
                if self.isPlaying, Date().timeIntervalSince(self.lastSave) >= 2 {
                    self.saveProgress()
                }
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
        playbackSpeed = current?.bookID.flatMap { history.books[$0]?.speed } ?? 1
        if current?.bookID != nil { repeatMode = .off }
        syncPlayerItems(fullRebuild: true)
        beginPlayback()
        saveProgress()
    }

    /// Plays the tracks shuffled, starting from a RANDOM track — the
    /// iTunes/Music behavior every Shuffle button expects. (Plain `play` +
    /// `toggleShuffle` would always start on the collection's first track,
    /// because shuffling pins the current track at the head.)
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
            player.pause()
            isPlaying = false
            resumeAfterInterruption = false
            saveProgress()
        } else {
            if player.currentItem?.status == .failed {
                let retryTime = currentTime
                syncPlayerItems(fullRebuild: true)
                if retryTime > 0 { seek(to: retryTime) }
            } else if pendingSeekTarget != nil, activeSeekGeneration == nil {
                pendingSeekRetryCount = 0
                performPendingSeek(generation: seekGeneration)
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
        let generation = seekGeneration
        pendingSeekTarget = clamped
        pendingSeekItemID = player.currentItem.map(ObjectIdentifier.init)
        pendingSeek = true
        activeSeekGeneration = nil
        pendingSeekRetryCount = 0
        performPendingSeek(generation: generation)
    }

    private func performPendingSeek(generation: Int) {
        guard canSeek, let target = pendingSeekTarget, let item = player.currentItem,
              pendingSeekItemID == ObjectIdentifier(item), activeSeekGeneration != generation else { return }
        let itemID = ObjectIdentifier(item)
        let clampedTarget = currentDuration > 0 ? min(target, currentDuration) : target
        currentTime = clampedTarget
        pendingSeek = true
        activeSeekGeneration = generation
        let time = CMTime(seconds: clampedTarget, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.seekGeneration == generation,
                      self.player.currentItem.map(ObjectIdentifier.init) == itemID,
                      self.pendingSeekItemID == itemID else { return }
                self.activeSeekGeneration = nil
                guard finished else {
                    guard self.pendingSeekRetryCount < 3 else {
                        self.player.pause()
                        self.isPlaying = false
                        self.resumeAfterInterruption = false
                        self.playbackNotice = "The chapter couldn’t move to that position. Adjust the slider or press Play to try again. Your saved position is unchanged."
                        return
                    }
                    self.pendingSeekRetryCount += 1
                    // swiftformat:disable redundantSelf
                    // Nested in an escaping closure, so `self.` is required here.
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(100))
                        guard let self, self.seekGeneration == generation,
                              self.pendingSeekItemID == itemID else { return }
                        self.performPendingSeek(generation: generation)
                    }
                    // swiftformat:enable redundantSelf
                    return
                }
                self.pendingSeek = false
                self.pendingSeekTarget = nil
                self.pendingSeekItemID = nil
                self.pendingSeekRetryCount = 0
                self.hasAuthoritativeCurrentTime = true
                self.saveProgress()
            }
        }
    }

    public func skip(by seconds: TimeInterval) {
        let itemTime = player.currentItem?.currentTime().seconds
        let actual = itemTime?.isFinite == true ? itemTime! : currentTime
        seek(to: (pendingSeekTarget ?? actual) + seconds)
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
        let bookmark = history.books[bookID]
        let index = bookmark.flatMap { mark in tracks.firstIndex { $0.relativePath == mark.path } } ?? 0
        guard prepareForPlayback(tracks[bookmark?.finished == true ? 0 : index]) else { return }
        play(tracks, startingAt: bookmark?.finished == true ? 0 : index)
        if let bookmark, !bookmark.finished,
           current?.relativePath == bookmark.path { seek(to: bookmark.seconds) }
    }

    public func bookProgress(_ bookID: String) -> (path: String, seconds: Double, finished: Bool)? {
        guard let mark = history.books[bookID] else { return nil }
        return (mark.path, mark.seconds, mark.finished)
    }

    /// Called after the first index snapshot. Re-resolve URLs from the current
    /// root and omit missing tracks; never start audio on launch.
    public func restoreSession(available: [PlayableTrack]) {
        guard !hasRestored else { return }
        if current != nil || history.session == nil { hasRestored = true; return }
        guard current == nil, let session = history.session,
              session.paths.indices.contains(session.index) else { return }
        let byPath = Dictionary(available.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        let remaining = session.paths.enumerated().compactMap { index, path in byPath[path].map { (index, $0) } }
        guard !remaining.isEmpty else { return }
        let restoredIndex = remaining.firstIndex { $0.0 == session.index } ?? 0
        // Wait for cloud metadata/download instead of clamping a saved
        // position to zero against a temporary zero-duration placeholder.
        guard remaining[restoredIndex].1.isDownloaded else { return }
        hasRestored = true
        let wasFinished = remaining[restoredIndex].1.bookID.flatMap { history.books[$0]?.finished } ?? false
        queue.replace(with: remaining.map(\.1), startingAt: restoredIndex)
        playbackSpeed = Self.supportedSpeeds.contains(session.speed) ? session.speed : 1
        syncPlayerItems(fullRebuild: true)
        if remaining[restoredIndex].0 == session.index { seek(to: session.seconds) }
        bookFinished = wasFinished
        saveProgress()
    }

    public func saveProgress() {
        if let current, let index = queue.currentIndex, currentTime.isFinite,
           hasAuthoritativeCurrentTime
        {
            history.session = .init(paths: queue.items.map(\.relativePath), index: index,
                                    seconds: currentTime, speed: playbackSpeed)
            if let bookID = current.bookID {
                history.books[bookID] = .init(path: current.relativePath, seconds: currentTime,
                                              speed: playbackSpeed, finished: bookFinished)
            }
        }
        persistHistory()
    }

    private func persistHistory() {
        guard let historyURL else { return }
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(history).write(to: historyURL, options: .atomic)
            progressSaveFailed = false
            lastSave = Date()
        } catch {
            progressSaveFailed = true
            Self.logger.error("Could not save listening progress: \(error)")
        }
    }

    /// Reconciles the in-memory queue and device-local resume history after
    /// files have actually reached Trash. Removing a queued item never
    /// interrupts a surviving current item; removing the current item parks
    /// on the nearest survivor, paused at its beginning.
    public func removeDeletedLibraryItems(
        relativePaths: Set<String>,
        bookIDs: Set<String> = []
    ) {
        guard !relativePaths.isEmpty || !bookIDs.isEmpty else { return }

        func shouldRemove(_ path: String) -> Bool {
            if relativePaths.contains(path) { return true }
            return bookIDs.contains { path.hasPrefix("Audiobooks/\($0)/") }
        }

        saveProgress()
        let outcome = queue.remove(relativePaths: relativePaths, bookIDs: bookIDs)

        for bookID in bookIDs {
            history.books.removeValue(forKey: bookID)
        }
        history.books = history.books.filter { !shouldRemove($0.value.path) }
        if let session = history.session {
            let survivors = session.paths.enumerated().filter { !shouldRemove($0.element) }
            if survivors.isEmpty {
                history.session = nil
            } else {
                let oldCurrent = session.paths.indices.contains(session.index) ? session.index : 0
                let selected = survivors.first(where: { $0.offset == oldCurrent })
                    ?? survivors.first(where: { $0.offset > oldCurrent })
                    ?? survivors.last!
                history.session = .init(
                    paths: survivors.map(\.element),
                    index: survivors.firstIndex { $0.offset == selected.offset } ?? 0,
                    seconds: selected.offset == oldCurrent ? session.seconds : 0,
                    speed: session.speed
                )
            }
        }

        switch outcome {
        case .unchanged:
            break
        case .currentPreserved:
            syncPlayerItems(fullRebuild: false)
        case .currentReplaced, .emptied:
            player.pause()
            isPlaying = false
            resumeAfterInterruption = false
            seekGeneration += 1
            pendingSeek = false
            pendingSeekTarget = nil
            pendingSeekItemID = nil
            activeSeekGeneration = nil
            pendingSeekRetryCount = 0
            currentTime = 0
            currentDuration = current?.duration ?? 0
            canSeek = currentDuration > 0 && current?.isDownloaded == true
            hasAuthoritativeCurrentTime = false
            bookFinished = false
            playbackNotice = nil
            playbackSpeed = current?.bookID.flatMap { history.books[$0]?.speed } ?? 1
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

    /// Inserts every track right after the current one, preserving `tracks`'
    /// order — the single home for the "insert reversed" trick: each track is
    /// individually inserted right after the current item, so inserting the
    /// batch back-to-front leaves the batch in its original order ahead of
    /// whatever was already queued.
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

    /// No UI exposes stop today (pause is the product's idle state); this
    /// exists for tests and completeness.
    public func stop() {
        player.pause()
        isPlaying = false
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

    /// Rebuilds the player's item list from the queue. `fullRebuild` clears
    /// everything (used when the *current* item changed); otherwise only the
    /// tail (the preloaded "next" item) is replaced, so a currently-playing
    /// item is never interrupted just because `upNext` changed (e.g. a
    /// repeat-mode toggle).
    private func syncPlayerItems(fullRebuild: Bool) {
        guard let current = queue.current else {
            player.pause()
            isPlaying = false
            currentTime = 0
            currentDuration = 0
            canSeek = false
            hasAuthoritativeCurrentTime = false
            removeEndOfItemObserver()
            player.removeAllItems()
            itemTracks.removeAll()
            itemStatusObservations.removeAll()
            return
        }

        if fullRebuild {
            seekGeneration += 1
            pendingSeek = false
            pendingSeekTarget = nil
            pendingSeekItemID = nil
            activeSeekGeneration = nil
            pendingSeekRetryCount = 0
            currentTime = 0
            currentDuration = current.duration.isFinite ? max(current.duration, 0) : 0
            canSeek = false
            hasAuthoritativeCurrentTime = false
            player.removeAllItems()
            itemTracks.removeAll()
            itemStatusObservations.removeAll()
            let currentItem = makeItem(for: current)
            player.insert(currentItem, after: nil)
            observeStatus(of: currentItem)
            resolveDuration(for: currentItem)
            observeEndOfItem(currentItem)
        } else {
            // Keep the currently playing item; only touch what comes after it.
            let items = player.items()
            if let head = items.first {
                for tail in items.dropFirst() {
                    player.remove(tail)
                    itemTracks.removeValue(forKey: ObjectIdentifier(tail))
                    itemStatusObservations.removeValue(forKey: ObjectIdentifier(tail))
                }
                resolveDuration(for: head)
                observeEndOfItem(head)
            } else {
                let currentItem = makeItem(for: current)
                player.insert(currentItem, after: nil)
                observeStatus(of: currentItem)
                resolveDuration(for: currentItem)
                observeEndOfItem(currentItem)
            }
        }

        if let upNext = queue.upNext(repeatMode: repeatMode) {
            let nextItem = makeItem(for: upNext)
            player.insert(nextItem, after: player.items().first)
            observeStatus(of: nextItem)
        }
    }

    private func makeItem(for track: PlayableTrack) -> AVPlayerItem {
        // Every play path funnels through here, so this is the one place that
        // guarantees an undownloaded iCloud file gets its download kicked off
        // — the item itself will fail (and be skipped) this time around, but
        // the bytes arrive for the next attempt.
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
                let seconds = duration.seconds
                currentDuration = seconds
                canSeek = true
                playbackNotice = nil
                performPendingSeek(generation: seekGeneration)
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
            guard player.currentItem.map(ObjectIdentifier.init) == itemID else { return }
            if let item = player.currentItem {
                updateDurationIfAvailable(from: item)
                resolveDuration(for: item)
            }
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
        if pendingSeekTarget != nil { performPendingSeek(generation: seekGeneration) }
    }

    public func refreshAvailableTracks(_ tracks: [PlayableTrack]) {
        queue.refreshMetadata(from: tracks)
        guard let current else { return }
        if current.duration > 0, current.duration.isFinite {
            currentDuration = max(currentDuration, current.duration)
            canSeek = player.currentItem?.status == .readyToPlay && current.isDownloaded
            if pendingSeekTarget != nil { performPendingSeek(generation: seekGeneration) }
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

    /// Invariant this relies on: `upNext(repeatMode: .one)` always preloads
    /// the *same* track as the one that just ended, so when `.actionAtItemEnd
    /// == .advance` moves the player into that preloaded duplicate item, we
    /// simply let it keep playing and re-arm the next preloaded duplicate —
    /// there's no seek-to-zero needed, and no visible gap. (The alternative
    /// of seeking the *same* item back to zero was considered, but that
    /// would fight the player's own auto-advance into the duplicate and
    /// require tearing down/re-adding items anyway.)
    private func handleItemDidEnd() {
        seekGeneration += 1
        pendingSeek = false
        pendingSeekTarget = nil
        pendingSeekItemID = nil
        activeSeekGeneration = nil
        pendingSeekRetryCount = 0
        bookFinished = queue.upNext(repeatMode: repeatMode) == nil && current?.bookID != nil
        currentTime = currentDuration
        hasAuthoritativeCurrentTime = true
        saveProgress()
        currentTime = 0
        currentDuration = 0
        canSeek = false
        hasAuthoritativeCurrentTime = false
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
            saveProgress()
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
            currentDuration = track.duration.isFinite ? max(track.duration, 0) : 0
            canSeek = currentDuration > 0
            updateDurationIfAvailable(from: playingItem)
            resolveDuration(for: playingItem)
            observeEndOfItem(playingItem)
            // Top up the tail with the next preload.
            if let upNext = queue.upNext(repeatMode: repeatMode) {
                let items = player.items()
                for tail in items.dropFirst() {
                    player.remove(tail)
                    itemTracks.removeValue(forKey: ObjectIdentifier(tail))
                    itemStatusObservations.removeValue(forKey: ObjectIdentifier(tail))
                }
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

    private func handleItemFailure(_ failedItemID: ObjectIdentifier?) {
        guard let failedItemID, itemTracks[failedItemID] != nil else { return }
        // A PRELOADED item can fail while the current one plays fine (bad
        // file, undownloaded iCloud placeholder). Only skip when the failure
        // is the item actually playing; otherwise just drop the bad preload —
        // if playback reaches that track it will fail again as current and be
        // skipped then.
        //
        // `player.currentItem` can't be used to tell which case this is:
        // with `actionAtItemEnd == .advance`, AVQueuePlayer discards a failed
        // item and promotes whatever was preloaded next to `currentItem`
        // itself, synchronously and before this (asynchronously-dispatched)
        // handler runs — so by the time we get here, `player.currentItem` may
        // already be the *next* item even though the failure was ours.
        // Compare the failed item's own tracked track against the queue's
        // `current` instead, which isn't affected by the player's own
        // auto-advance.
        if itemTracks[failedItemID] == current?.relativePath {
            if current?.bookID != nil {
                player.pause()
                isPlaying = false
                resumeAfterInterruption = false
                seekGeneration += 1
                pendingSeek = false
                pendingSeekTarget = nil
                pendingSeekItemID = nil
                activeSeekGeneration = nil
                pendingSeekRetryCount = 0
                canSeek = false
                hasAuthoritativeCurrentTime = false
                playbackNotice = "This chapter couldn’t be played. Try again after it finishes downloading. Your saved position is unchanged."
                return
            }
            Self.logger.error("Playing item failed; skipping to next track.")
            guard queue.upNext(repeatMode: repeatMode) != nil else {
                // No further track to skip to — `next()` would be a no-op
                // here (it only moves `currentIndex` when there's somewhere
                // to move it to), which would leave `isPlaying` stuck `true`
                // over a track that will never play. Stop cleanly instead,
                // mirroring the equivalent tail case in `handleItemDidEnd`.
                player.pause()
                isPlaying = false
                resumeAfterInterruption = false
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
