import CloudFiles
import Domain
import Foundation
import LibraryStore
import MetadataImport
import NowPlaying
import Observation
import PlaybackEngine
import SwiftData

/// Non-UI coordinator that owns the library's SwiftData container, artwork
/// cache, and folder watcher, and pumps file-system diffs into the indexer.
/// Also owns the playback stack: the `PlayerController` and its
/// `NowPlayingBridge` to the lock screen / Control Center / media keys.
@MainActor
@Observable
public final class LibraryCoordinator {
    public let container: ModelContainer
    public let libraryRoot: URL
    public let player: PlayerController
    public let nowPlaying: NowPlayingBridge

    private let watcher: any LibraryFolderWatching
    private let artwork: ArtworkStore
    private var watchTask: Task<Void, Never>?

    /// Default stack: `LibraryContainerFactory`'s default container, an
    /// `ArtworkStore` at `<App Support>/theoldpod/Artwork`, and a
    /// `LocalFolderWatcher` rooted at `LibraryLocation.defaultRoot()`.
    public init() throws {
        let root = try LibraryLocation.defaultRoot()
        container = try LibraryContainerFactory.make(storeURL: nil)
        let artworkDirectory = try Self.defaultArtworkDirectory()
        artwork = try ArtworkStore(directory: artworkDirectory)
        watcher = LocalFolderWatcher(root: root)
        libraryRoot = root
        let player = PlayerController()
        self.player = player
        nowPlaying = NowPlayingBridge(player: player, artworkDirectory: artworkDirectory)
    }

    /// For tests and previews: inject every collaborator.
    public init(
        container: ModelContainer,
        watcher: any LibraryFolderWatching,
        artwork: ArtworkStore,
        libraryRoot: URL
    ) {
        self.container = container
        self.watcher = watcher
        self.artwork = artwork
        self.libraryRoot = libraryRoot
        let player = PlayerController()
        self.player = player
        nowPlaying = NowPlayingBridge(player: player, artworkDirectory: artwork.directory)
    }

    /// Idempotent: starts a task consuming `watcher.changes()` into the
    /// indexer, and activates the now-playing bridge. Calling this again
    /// while already running is a no-op.
    public func start() {
        guard watchTask == nil else { return }
        let container = container
        let artwork = artwork
        let watcher = watcher
        watchTask = Task {
            let indexer = LibraryIndexer(modelContainer: container, artwork: artwork)
            for await changes in watcher.changes() {
                await indexer.apply(changes)
            }
        }
        nowPlaying.activate()
    }

    /// Snapshots SwiftData `Track`s into `PlayableTrack` values suitable for
    /// handing to `player.play(_:startingAt:)`.
    public func playableTracks(from tracks: [Track]) -> [PlayableTrack] {
        tracks.map { PlayableTrack(track: $0, libraryRoot: libraryRoot) }
    }

    public func stop() {
        watcher.stop()
        watchTask?.cancel()
        watchTask = nil
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
