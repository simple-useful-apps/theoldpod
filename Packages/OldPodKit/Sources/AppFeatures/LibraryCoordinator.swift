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

/// Wires the library together: the SwiftData container, artwork cache and
/// folder watcher feeding the indexer; the playback stack; and the stores
/// views act through (playlists, imports, book preparation). Playlists live
/// as `.m3u8` files under `<libraryRoot>/Playlists`, so the SwiftData store
/// stays rebuildable from the library folder, same as `Track`s.
@MainActor
@Observable
public final class LibraryCoordinator {
    public let container: ModelContainer
    public let libraryRoot: URL
    public let isCloudLibrary: Bool
    public let player: PlayerController
    public let nowPlaying: NowPlayingBridge
    public let playlists: PlaylistStore
    public let books: BookPreparer
    public private(set) var importer: LibraryImporter!
    public private(set) var lastChecked: Date?
    public private(set) var refreshError: String?
    public private(set) var isDeletingLibraryItems = false

    private let watcher: any LibraryFolderWatching
    private let artwork: ArtworkStore
    private let playlistSync: PlaylistFileSync
    private let deletionService: LibraryDeletionService
    private let indexer: LibraryIndexer
    #if os(macOS)
        private let metadataEditor: AudioMetadataEditor
    #endif
    private var watchTask: Task<Void, Never>?
    private var refreshRequests: [UUID: RefreshRequest] = [:]

    /// A refresh waiting for the index to confirm that the given files are
    /// gone. A plain refresh has nothing to confirm and completes on the next
    /// saved batch.
    private struct RefreshRequest {
        let absentPaths: Set<String>
        let absentBookIDs: Set<String>
        let continuation: CheckedContinuation<Bool, Never>

        func isSatisfied(by indexedPaths: Set<String>) -> Bool {
            guard absentPaths.isDisjoint(with: indexedPaths) else { return false }
            return absentBookIDs.allSatisfy { bookID in
                !indexedPaths.contains { $0.hasPrefix("Audiobooks/\(bookID)/") }
            }
        }
    }

    /// Where `ArtworkStore` caches embedded artwork, for views that render it.
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
        let indexer = LibraryIndexer(modelContainer: container, artwork: artwork)
        self.indexer = indexer
        deletionService = LibraryDeletionService(libraryRoot: libraryRoot)
        #if os(macOS)
            metadataEditor = AudioMetadataEditor(libraryRoot: libraryRoot)
        #endif
        let player = PlayerController(historyURL: artwork.directory.deletingLastPathComponent()
            .appendingPathComponent("ListeningHistory.json"))
        self.player = player
        nowPlaying = NowPlayingBridge(player: player, artworkDirectory: artwork.directory)

        let playlistsDirectory = libraryRoot.appendingPathComponent("Playlists", isDirectory: true)
        playlistSync = PlaylistFileSync(store: PlaylistFileStore(directory: playlistsDirectory), container: container)
        playlists = PlaylistStore(context: container.mainContext, files: playlistSync)
        books = BookPreparer(libraryRoot: libraryRoot, container: container, indexer: indexer) {
            Self.refreshPlayableTracks(in: container, libraryRoot: libraryRoot, player: player)
        }
        importer = LibraryImporter(libraryRoot: libraryRoot) { [weak self] in
            _ = await self?.refreshLibrary()
        }
    }

    /// Resolves the library location (iCloud when available, else the local
    /// fallback) and builds the coordinator around it. `nil` only if the
    /// model container or artwork store cannot be set up; use
    /// `makeResult()` to learn why.
    @MainActor
    public static func make() async -> LibraryCoordinator? {
        try? await makeResult().get()
    }

    /// Like `make()`, but a failure carries a human-readable reason and the
    /// library folder that was being set up, so the app's setup-failure
    /// screen can explain itself and offer a retry.
    @MainActor
    public static func makeResult() async -> Result<LibraryCoordinator, LibrarySetupError> {
        let logger = Logger(subsystem: "OldPodKit.AppFeatures", category: "LibraryCoordinator")
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
                    return .success(LibraryCoordinator(
                        container: container,
                        watcher: LocalFolderWatcher(root: root),
                        artwork: ArtworkStore(directory: root.appendingPathComponent(".artwork")),
                        libraryRoot: root
                    ))
                } catch {
                    logger.fault("Acceptance library setup failed at \(path, privacy: .public): \(error)")
                    return .failure(LibrarySetupError(underlying: error, libraryFolder: root))
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
            return .success(LibraryCoordinator(
                container: container,
                watcher: watcher,
                artwork: artwork,
                libraryRoot: resolved.root,
                isCloudLibrary: resolved.isCloud
            ))
        } catch {
            logger.fault("Library setup failed: \(error)")
            return .failure(LibrarySetupError(underlying: error, libraryFolder: resolved.root))
        }
    }

    /// Starts indexing folder changes, activates the now-playing bridge, and
    /// brings playlist file sync online. Calling it again is a no-op.
    public func start() {
        guard watchTask == nil else { return }
        watchTask = Task { [watcher, indexer] in
            // The first emission is the watcher's full snapshot, and it is
            // authoritative: rows for files missing under the current root
            // are pruned. Later emissions are incremental diffs.
            var isInitialSnapshot = true
            for await changes in watcher.changes() {
                // A refresh requested while this batch is indexing waits for
                // the next one.
                let pending = refreshRequests
                let indexedPaths = await indexer.apply(changes, reconcilingFullSnapshot: isInitialSnapshot)
                isInitialSnapshot = false
                if indexedPaths != nil {
                    refreshPlayableTracks()
                    lastChecked = Date()
                } else {
                    refreshError = "Library changes couldn’t be saved. Check available storage and try again."
                }
                for (id, request) in pending {
                    guard let indexedPaths else {
                        completeRefresh(id, succeeded: false)
                        continue
                    }
                    if request.isSatisfied(by: indexedPaths) {
                        completeRefresh(id, succeeded: true)
                    }
                }
            }
        }
        nowPlaying.activate()
        playlistSync.migrateAndReconcile()
        playlistSync.startWatching()
    }

    public func playableTracks(from tracks: [Track]) -> [PlayableTrack] {
        let albumArtwork = tracks.contains { $0.artworkID == nil }
            ? Self.albumArtworkIndex(container.mainContext)
            : [:]
        return tracks.map { Self.playable($0, libraryRoot: libraryRoot, albumArtwork: albumArtwork) }
    }

    /// Album key → the first embedded artwork found on that album, so tracks
    /// without their own art show their album's in Now Playing and on the
    /// lock screen.
    private static func albumArtworkIndex(_ context: ModelContext) -> [String: String] {
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.artworkID != nil })
        let tracksWithArt = (try? context.fetch(descriptor)) ?? []
        return albumArtworkIndex(tracksWithArt)
    }

    private static func albumArtworkIndex(_ tracks: [Track]) -> [String: String] {
        var index: [String: String] = [:]
        for track in tracks {
            guard let artworkID = track.artworkID, let key = albumKey(track) else { continue }
            if index[key] == nil { index[key] = artworkID }
        }
        return index
    }

    /// Same (album artist, album) pairing `LibraryGroups` uses; untitled
    /// albums don't share art.
    private static func albumKey(_ track: Track) -> String? {
        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !album.isEmpty else { return nil }
        let artist = (track.albumArtist ?? track.artist).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return artist + "\u{1F}" + album
    }

    private static func playable(_ track: Track, libraryRoot: URL, albumArtwork: [String: String]) -> PlayableTrack {
        let fallback = track.artworkID == nil ? albumKey(track).flatMap { albumArtwork[$0] } : nil
        return PlayableTrack(track: track, libraryRoot: libraryRoot, fallbackArtworkID: fallback)
    }

    /// Rescans the library folder and waits for the index to catch up.
    /// Returns `false` if the folder could not be read or the index did not
    /// confirm the change within a reasonable time.
    @discardableResult
    public func refreshLibrary() async -> Bool {
        await refreshLibrary(untilAbsent: [], bookIDs: [])
    }

    private func refreshLibrary(untilAbsent absentPaths: Set<String>, bookIDs absentBookIDs: Set<String>) async -> Bool {
        refreshError = nil
        let id = UUID()
        return await withCheckedContinuation { continuation in
            refreshRequests[id] = RefreshRequest(
                absentPaths: absentPaths,
                absentBookIDs: absentBookIDs,
                continuation: continuation
            )
            Task {
                try? await Task.sleep(for: .seconds(15))
                guard refreshRequests[id] != nil else { return }
                refreshError = "The library check is still pending. Try refreshing again if the list doesn’t update."
                completeRefresh(id, succeeded: false)
            }
            Task {
                do {
                    try await watcher.refresh()
                    playlistSync.reconcile()
                } catch {
                    refreshError = "The library folder couldn’t be read. Check that it’s available and try again."
                    completeRefresh(id, succeeded: false)
                }
            }
        }
    }

    /// Moves the requested library-owned song files to Trash. SwiftData is
    /// updated only by the folder watcher after the files have moved.
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
            if await !refreshLibrary(untilAbsent: succeeded, bookIDs: []) {
                result = result.withPostDeletionWarning()
            }
        }
        return result
    }

    /// Moves `Audiobooks/<name>` and all of its contents to Trash.
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
            if await !refreshLibrary(untilAbsent: [], bookIDs: [name]) {
                result = result.withPostDeletionWarning()
            }
        }
        return result
    }

    #if os(macOS)
        /// Reads the embedded tags for Get Info rather than the index row,
        /// whose title may be a filename fallback.
        public func metadataEditSession(for relativePath: String) async throws -> AudioMetadataEditSession {
            guard AudiobookPath.bookID(for: relativePath) == nil else {
                throw AudioMetadataEditorError.unsupportedFile
            }
            return try await metadataEditor.load(relativePath: relativePath)
        }

        /// Updates the file, then refreshes its one index row and the queue's
        /// snapshots in place, without replacing the current player item.
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
            if let version = FileVersion.current(at: url),
               let metadata = try? await MetadataReader.read(from: url),
               await indexer.applyMetadataRefreshes([
                   LibraryMetadataRefresh(relativePath: relativePath, url: url, metadata: metadata, fileVersion: version),
               ]).contains(relativePath)
            {
                refreshPlayableTracks()
                lastChecked = Date()
            } else {
                await refreshLibrary()
            }
            return true
        }
    #endif

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

    /// Hands the player fresh snapshots of every track, so queued items pick
    /// up new metadata and a saved session can be restored once its files
    /// are indexed.
    private func refreshPlayableTracks() {
        Self.refreshPlayableTracks(in: container, libraryRoot: libraryRoot, player: player)
    }

    private static func refreshPlayableTracks(in container: ModelContainer, libraryRoot: URL, player: PlayerController) {
        guard let tracks = try? container.mainContext.fetch(FetchDescriptor<Track>()) else { return }
        let albumArtwork = albumArtworkIndex(tracks)
        let playable = tracks.map { Self.playable($0, libraryRoot: libraryRoot, albumArtwork: albumArtwork) }
        player.restoreSession(available: playable)
        player.refreshAvailableTracks(playable)
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

    private func completeRefresh(_ id: UUID, succeeded: Bool) {
        refreshRequests.removeValue(forKey: id)?.continuation.resume(returning: succeeded)
    }
}

private extension LibraryDeletionResult {
    func withPostDeletionWarning() -> LibraryDeletionResult {
        LibraryDeletionResult(
            successfulTargets: successfulTargets,
            alreadyMissingTargets: alreadyMissingTargets,
            failures: failures,
            postDeletionWarning: "The selected files were moved to Trash. "
                + "The library check is still pending or didn’t finish. Use Refresh Library if the list doesn’t update."
        )
    }
}

/// Why `LibraryCoordinator.makeResult()` could not build the library, for the
/// app's setup-failure screen.
public struct LibrarySetupError: Error, Sendable {
    /// The underlying error's description (Foundation errors already read as
    /// sentences, e.g. "You don't have permission to save the file…").
    public let reason: String
    /// The library folder that was being set up, when it had been resolved.
    public let libraryFolder: URL?

    public init(reason: String, libraryFolder: URL?) {
        self.reason = reason
        self.libraryFolder = libraryFolder
    }

    init(underlying error: any Error, libraryFolder: URL?) {
        self.init(reason: error.localizedDescription, libraryFolder: libraryFolder)
    }
}
