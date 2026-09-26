import CloudFiles
import Domain
import Foundation
import LibraryStore
import MetadataImport
import NowPlaying
import Observation
import os
import PlaybackEngine
import SwiftData

public enum BookPreparationState: Sendable, Equatable {
    case preparing(completed: Int, total: Int)
    case ready
    case failed(String)
}

/// Non-UI coordinator that owns the library's SwiftData container, artwork
/// cache, and folder watcher, and pumps file-system diffs into the indexer.
/// Also owns the playback stack: the `PlayerController` and its
/// `NowPlayingBridge` to the lock screen / Control Center / media keys.
///
/// Also owns playlist file sync: playlists live as `.m3u8` files under
/// `<libraryRoot>/Playlists`, so the SwiftData store stays rebuildable from
/// the library folder per `CLAUDE.md`, same as `Track`s.
@MainActor
@Observable
public final class LibraryCoordinator {
    public let container: ModelContainer
    public let libraryRoot: URL
    public let isCloudLibrary: Bool
    public let player: PlayerController
    public let nowPlaying: NowPlayingBridge
    public private(set) var importer: LibraryImporter!
    public private(set) var lastChecked: Date?
    public private(set) var refreshError: String?
    public private(set) var isDeletingLibraryItems = false
    public private(set) var bookPreparation: [String: BookPreparationState] = [:]

    private let watcher: any LibraryFolderWatching
    private let artwork: ArtworkStore
    private let playlistSync: PlaylistFileSync
    private let deletionService: LibraryDeletionService
    private let indexer: LibraryIndexer
    #if os(macOS)
        private let metadataEditor: AudioMetadataEditor
    #endif
    private var watchTask: Task<Void, Never>?
    private var refreshWaiters: [UUID: RefreshWaiter] = [:]

    private struct RefreshExpectation {
        let absentPaths: Set<String>
        let absentBookIDs: Set<String>

        func isSatisfied(by indexedPaths: Set<String>) -> Bool {
            guard absentPaths.isDisjoint(with: indexedPaths) else { return false }
            return absentBookIDs.allSatisfy { bookID in
                !indexedPaths.contains { $0.hasPrefix("Audiobooks/\(bookID)/") }
            }
        }
    }

    private struct RefreshWaiter {
        let continuation: CheckedContinuation<Bool, Never>
        let expectation: RefreshExpectation
    }

    /// Where `ArtworkStore` caches embedded artwork, for views (`ArtworkImage`,
    /// `NowPlayingView`) that render it directly.
    public var artworkDirectory: URL {
        artwork.directory
    }

    /// For tests and previews: inject every collaborator.
    public init(
        container: ModelContainer,
        watcher: any LibraryFolderWatching,
        artwork: ArtworkStore,
        libraryRoot: URL,
        isCloudLibrary: Bool = false
    ) {
        self.container = container
        self.watcher = watcher
        self.artwork = artwork
        self.libraryRoot = libraryRoot
        self.isCloudLibrary = isCloudLibrary
        indexer = LibraryIndexer(modelContainer: container, artwork: artwork)
        deletionService = LibraryDeletionService(libraryRoot: libraryRoot)
        #if os(macOS)
            metadataEditor = AudioMetadataEditor(libraryRoot: libraryRoot)
        #endif
        let player = PlayerController(historyURL: artwork.directory.deletingLastPathComponent()
            .appendingPathComponent("ListeningHistory.json"))
        self.player = player
        nowPlaying = NowPlayingBridge(player: player, artworkDirectory: artwork.directory)

        let playlistsDirectory = libraryRoot.appendingPathComponent("Playlists", isDirectory: true)
        let playlistSync = PlaylistFileSync(store: PlaylistFileStore(directory: playlistsDirectory), container: container)
        self.playlistSync = playlistSync
        PlaylistOps.fileSync = playlistSync
        importer = LibraryImporter(libraryRoot: libraryRoot) { [weak self] in
            _ = await self?.refreshLibrary()
        }
    }

    /// Resolves the library location (cloud if available, else the local
    /// fallback — see `LibraryLocation.resolve()`) and builds the full
    /// coordinator stack around it. `nil` only if setting up the model
    /// container or artwork store throws, which local-only `init()` would
    /// also fail on.
    @MainActor
    public static func make() async -> LibraryCoordinator? {
        #if DEBUG
            // Acceptance runs use their own files and index, without touching
            // the user's music or iCloud container. The directory must already
            // exist (and be accessible inside the app's sandbox).
            if let path = ProcessInfo.processInfo.environment["OLDPOD_ACCEPTANCE_ROOT"] {
                let root = URL(fileURLWithPath: path, isDirectory: true)
                do {
                    let container = try LibraryContainerFactory.make(
                        storeURL: root.appendingPathComponent(".index/Library.store")
                    )
                    return LibraryCoordinator(
                        container: container,
                        watcher: LocalFolderWatcher(root: root),
                        artwork: ArtworkStore(directory: root.appendingPathComponent(".artwork")),
                        libraryRoot: root
                    )
                } catch {
                    Logger(subsystem: "OldPodKit.AppFeatures", category: "LibraryCoordinator")
                        .fault("Acceptance library setup failed at \(path, privacy: .public): \(error)")
                    return nil
                }
            }
        #endif
        let resolved = await LibraryLocation.resolve()
        do {
            let container = try LibraryContainerFactory.make(storeURL: nil)
            let artworkDirectory = try defaultArtworkDirectory()
            let artwork = ArtworkStore(directory: artworkDirectory)
            let watcher: any LibraryFolderWatching = resolved.isCloud
                ? UbiquityLibraryWatcher(containerDocumentsMusicURL: resolved.root)
                : LocalFolderWatcher(root: resolved.root)
            return LibraryCoordinator(
                container: container,
                watcher: watcher,
                artwork: artwork,
                libraryRoot: resolved.root,
                isCloudLibrary: resolved.isCloud
            )
        } catch {
            // Surfaced in the UI only as the generic failure screen — the
            // specifics land here (a silent catch hid a CloudKit-vs-SwiftData
            // misconfiguration for a whole debugging session).
            Logger(subsystem: "OldPodKit.AppFeatures", category: "LibraryCoordinator")
                .fault("Library setup failed: \(error)")
            return nil
        }
    }

    /// Idempotent: starts a task consuming `watcher.changes()` into the
    /// indexer, activates the now-playing bridge, and brings playlist file
    /// sync online (one-time migration + reconcile, then live watching).
    /// Calling this again while already running is a no-op.
    public func start() {
        guard watchTask == nil else { return }
        let container = container
        let watcher = watcher
        watchTask = Task {
            let indexer = self.indexer
            // The stream's first emission is the watcher's full snapshot
            // (LibraryFolderWatching contract). It is authoritative: rows for
            // files that no longer exist under the CURRENT root are pruned,
            // so switching roots (local → iCloud) can't leave a stale
            // library behind. Later emissions are incremental diffs.
            var isInitialSnapshot = true
            for await changes in watcher.changes() {
                // Capture before the actor hop. A refresh requested while an
                // older batch is indexing must wait for a later emission.
                let waitingForThisBatch = self.refreshWaiters
                let saved = await indexer.apply(changes, reconcilingFullSnapshot: isInitialSnapshot)
                if saved, let tracks = try? container.mainContext.fetch(FetchDescriptor<Track>()) {
                    let playable = self.playableTracks(from: tracks)
                    self.player.restoreSession(available: playable)
                    self.player.refreshAvailableTracks(playable)
                }
                isInitialSnapshot = false
                if saved {
                    self.lastChecked = Date()
                } else {
                    self.refreshError = "Library changes couldn’t be saved. Check available storage and try again."
                }
                let indexedPaths = saved ? try? await indexer.indexedRelativePaths() : nil
                for (id, waiter) in waitingForThisBatch {
                    if !saved {
                        self.completeRefreshWaiter(id, succeeded: false)
                    } else if let indexedPaths,
                              waiter.expectation.isSatisfied(by: indexedPaths)
                    {
                        self.completeRefreshWaiter(id, succeeded: true)
                    } else if indexedPaths == nil {
                        self.completeRefreshWaiter(id, succeeded: false)
                    }
                }
            }
        }
        nowPlaying.activate()
        playlistSync.migrateAndReconcile()
        playlistSync.startWatching()
    }

    /// Snapshots SwiftData `Track`s into `PlayableTrack` values suitable for
    /// handing to `player.play(_:startingAt:)`.
    public func playableTracks(from tracks: [Track]) -> [PlayableTrack] {
        tracks.map { PlayableTrack(track: $0, libraryRoot: libraryRoot) }
    }

    /// Loads only missing metadata for the book the user opened. Reads are
    /// bounded to three files at a time and the indexer refetches each row
    /// before applying results, so an in-flight read cannot resurrect a
    /// chapter deleted from the authoritative library folder.
    public func prepareBook(named name: String, relativePaths: [String]) async {
        guard !relativePaths.isEmpty else { return }
        let requested = Set(relativePaths)
        let descriptor = FetchDescriptor<Track>()
        guard let tracks = try? container.mainContext.fetch(descriptor) else { return }
        let missing = tracks.filter {
            requested.contains($0.relativePath) && (!$0.isDownloaded || $0.duration <= 0)
        }.map(\.relativePath)
        guard !missing.isEmpty else {
            bookPreparation[name] = .ready
            return
        }

        bookPreparation[name] = .preparing(completed: 0, total: missing.count)
        var completed = 0
        var failures: [String] = []
        for start in stride(from: 0, to: missing.count, by: 3) {
            guard !Task.isCancelled else { return }
            let batch = Array(missing[start ..< min(start + 3, missing.count)])
            let results = await withTaskGroup(of: LibraryMetadataRefresh?.self) { group in
                for path in batch {
                    let url = libraryRoot.appendingPathComponent(path)
                    group.addTask {
                        DownloadRequester.requestDownload(of: url)
                        for attempt in 0 ..< 4 {
                            if Task.isCancelled { return nil }
                            if let before = FileVersion.current(at: url),
                               let metadata = try? await MetadataReader.read(from: url), metadata.duration > 0,
                               FileVersion.current(at: url) == before
                            {
                                return LibraryMetadataRefresh(relativePath: path, url: url, metadata: metadata, fileVersion: before)
                            }
                            if attempt < 3 { try? await Task.sleep(for: .milliseconds(750)) }
                        }
                        return nil
                    }
                }
                var loaded: [LibraryMetadataRefresh] = []
                for await result in group {
                    if let result { loaded.append(result) }
                }
                return loaded
            }
            guard !Task.isCancelled else { return }
            let updated = await indexer.applyMetadataRefreshes(results)
            failures.append(contentsOf: batch.filter { !updated.contains($0) })
            completed += batch.count
            bookPreparation[name] = .preparing(completed: completed, total: missing.count)
        }

        if failures.isEmpty {
            bookPreparation[name] = .ready
        } else {
            bookPreparation[name] = .failed("Some chapter details aren’t available yet. Check your connection and try again.")
        }
        if let refreshed = try? container.mainContext.fetch(FetchDescriptor<Track>()) {
            player.refreshAvailableTracks(playableTracks(from: refreshed))
        }
    }

    // MARK: - Play conveniences

    @discardableResult
    public func refreshLibrary() async -> Bool {
        await refreshLibrary(requiringAbsentPaths: [], absentBookIDs: [])
    }

    private func refreshLibrary(
        requiringAbsentPaths absentPaths: Set<String>,
        absentBookIDs: Set<String>
    ) async -> Bool {
        refreshError = nil
        let waiterID = UUID()
        return await withCheckedContinuation { continuation in
            refreshWaiters[waiterID] = RefreshWaiter(
                continuation: continuation,
                expectation: RefreshExpectation(absentPaths: absentPaths, absentBookIDs: absentBookIDs)
            )
            Task {
                try? await Task.sleep(for: .seconds(15))
                guard refreshWaiters[waiterID] != nil else { return }
                refreshError = "The library check is still pending. Try refreshing again if the list doesn’t update."
                completeRefreshWaiter(waiterID, succeeded: false)
            }
            Task {
                do {
                    try await watcher.refresh()
                    playlistSync.reconcile()
                } catch {
                    refreshError = "The library folder couldn’t be read. Check that it’s available and try again."
                    completeRefreshWaiter(waiterID, succeeded: false)
                    return
                }
            }
        }
    }

    /// Moves the requested library-owned song files to Trash. SwiftData is
    /// updated only by the authoritative folder watcher after successful
    /// file operations.
    public func deleteSongs(relativePaths: [String]) async -> LibraryDeletionResult {
        guard !isDeletingLibraryItems else {
            return LibraryDeletionResult(failures: relativePaths.map {
                LibraryDeletionFailure(target: $0, message: "Another library deletion is still in progress.")
            })
        }
        isDeletingLibraryItems = true
        defer { isDeletingLibraryItems = false }

        var result = await deletionService.deleteSongs(relativePaths: relativePaths)
        let succeeded = Set(result.succeededTargets)
        if !succeeded.isEmpty {
            player.removeDeletedLibraryItems(relativePaths: succeeded)
            if await !refreshLibrary(requiringAbsentPaths: succeeded, absentBookIDs: []) {
                result = result.withPostDeletionWarning()
            }
        }
        return result
    }

    /// Moves exactly `Audiobooks/<name>` and all of its contents to Trash.
    public func deleteBook(named name: String) async -> LibraryDeletionResult {
        guard !isDeletingLibraryItems else {
            return LibraryDeletionResult(failures: [
                LibraryDeletionFailure(target: name, message: "Another library deletion is still in progress."),
            ])
        }
        isDeletingLibraryItems = true
        defer { isDeletingLibraryItems = false }

        var result = await deletionService.deleteBook(named: name)
        if result.isCompleteSuccess {
            player.removeDeletedLibraryItems(relativePaths: [], bookIDs: [name])
            if await !refreshLibrary(requiringAbsentPaths: [], absentBookIDs: [name]) {
                result = result.withPostDeletionWarning()
            }
        }
        return result
    }

    #if os(macOS)
        /// Reads the embedded values for Get Info instead of projecting the
        /// index row, whose title may be a filename fallback rather than a tag.
        public func metadataEditSession(for relativePath: String) async throws -> AudioMetadataEditSession {
            guard AudiobookPath.bookID(for: relativePath) == nil else {
                throw AudioMetadataEditorError.unsupportedFile
            }
            return try await metadataEditor.load(relativePath: relativePath)
        }

        /// Updates the source file, then refreshes the one SwiftData row and
        /// queue snapshots explicitly. `refreshAvailableTracks` changes the
        /// displayed metadata without replacing the current AVPlayerItem.
        @discardableResult
        public func updateMetadata(
            relativePath: String,
            fields: AudioMetadataFields,
            expectedVersion: AudioMetadataVersionToken
        ) async throws -> Bool {
            let changed = try await metadataEditor.update(
                relativePath: relativePath,
                fields: fields,
                expectedVersion: expectedVersion
            )
            guard changed else { return false }

            let url = libraryRoot.appendingPathComponent(relativePath)
            guard let version = FileVersion.current(at: url),
                  let metadata = try? await MetadataReader.read(from: url)
            else {
                _ = await refreshLibrary()
                return true
            }
            let refresh = LibraryMetadataRefresh(relativePath: relativePath, url: url, metadata: metadata, fileVersion: version)
            let updated = await indexer.applyMetadataRefreshes([refresh])
            if updated.contains(relativePath),
               let tracks = try? container.mainContext.fetch(FetchDescriptor<Track>())
            {
                player.refreshAvailableTracks(playableTracks(from: tracks))
                lastChecked = Date()
            } else {
                _ = await refreshLibrary()
            }
            return true
        }
    #endif

    /// Thin wrappers over `playableTracks(from:)` + `player`, so views never
    /// need to spell out that two-step dance themselves.
    public func play(_ tracks: [Track], startingAt index: Int = 0) {
        player.play(playableTracks(from: tracks), startingAt: index)
    }

    public func playShuffled(_ tracks: [Track]) {
        player.playShuffled(playableTracks(from: tracks))
    }

    public func playNext(_ tracks: [Track]) {
        player.playNext(playableTracks(from: tracks))
    }

    public func enqueue(_ tracks: [Track]) {
        player.append(playableTracks(from: tracks))
    }

    /// No production caller today — the coordinator lives for the whole
    /// process. Kept as the symmetric teardown for tests and any future
    /// library-root switching.
    public func stop() {
        player.saveProgress()
        watcher.stop()
        watchTask?.cancel()
        watchTask = nil
        completeRefreshWaiters(succeeded: false)
        playlistSync.stop()
        nowPlaying.deactivate()
    }

    private static func defaultArtworkDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = appSupport
            .appendingPathComponent("theoldpod", isDirectory: true)
            .appendingPathComponent("Artwork", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func completeRefreshWaiter(_ id: UUID, succeeded: Bool) {
        refreshWaiters.removeValue(forKey: id)?.continuation.resume(returning: succeeded)
    }

    private func completeRefreshWaiters(succeeded: Bool) {
        let waiters = refreshWaiters.values.map(\.continuation)
        refreshWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: succeeded)
        }
    }
}

private extension LibraryDeletionResult {
    func withPostDeletionWarning() -> LibraryDeletionResult {
        LibraryDeletionResult(
            successfulTargets: successfulTargets,
            alreadyMissingTargets: alreadyMissingTargets,
            failures: failures,
            postDeletionWarning: "The selected files were moved to Trash. The library check is still pending or didn’t finish. Use Refresh Library if the list doesn’t update."
        )
    }
}
