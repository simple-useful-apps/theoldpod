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

    private let watcher: any LibraryFolderWatching
    private let artwork: ArtworkStore
    private let playlistSync: PlaylistFileSync
    private var watchTask: Task<Void, Never>?

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
        let player = PlayerController()
        self.player = player
        nowPlaying = NowPlayingBridge(player: player, artworkDirectory: artwork.directory)

        let playlistsDirectory = libraryRoot.appendingPathComponent("Playlists", isDirectory: true)
        let playlistSync = PlaylistFileSync(store: PlaylistFileStore(directory: playlistsDirectory), container: container)
        self.playlistSync = playlistSync
        PlaylistOps.fileSync = playlistSync
    }

    /// Resolves the library location (cloud if available, else the local
    /// fallback — see `LibraryLocation.resolve()`) and builds the full
    /// coordinator stack around it. `nil` only if setting up the model
    /// container or artwork store throws, which local-only `init()` would
    /// also fail on.
    @MainActor
    public static func make() async -> LibraryCoordinator? {
        let resolved = await LibraryLocation.resolve()
        do {
            let container = try LibraryContainerFactory.make(storeURL: nil)
            let artworkDirectory = try defaultArtworkDirectory()
            let artwork = try ArtworkStore(directory: artworkDirectory)
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
        let artwork = artwork
        let watcher = watcher
        watchTask = Task {
            let indexer = LibraryIndexer(modelContainer: container, artwork: artwork)
            // The stream's first emission is the watcher's full snapshot
            // (LibraryFolderWatching contract). It is authoritative: rows for
            // files that no longer exist under the CURRENT root are pruned,
            // so switching roots (local → iCloud) can't leave a stale
            // library behind. Later emissions are incremental diffs.
            var isInitialSnapshot = true
            for await changes in watcher.changes() {
                await indexer.apply(changes, reconcilingFullSnapshot: isInitialSnapshot)
                isInitialSnapshot = false
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

    // MARK: - Play conveniences

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
        watcher.stop()
        watchTask?.cancel()
        watchTask = nil
        playlistSync.stop()
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
}
