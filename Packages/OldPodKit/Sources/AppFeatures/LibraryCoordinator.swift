import CloudFiles
import Foundation
import LibraryStore
import MetadataImport
import Observation
import SwiftData

/// Non-UI coordinator that owns the library's SwiftData container, artwork
/// cache, and folder watcher, and pumps file-system diffs into the indexer.
@MainActor
@Observable
public final class LibraryCoordinator {
    public let container: ModelContainer
    public let libraryRoot: URL

    private let watcher: any LibraryFolderWatching
    private let artwork: ArtworkStore
    private var watchTask: Task<Void, Never>?

    /// Default stack: `LibraryContainerFactory`'s default container, an
    /// `ArtworkStore` at `<App Support>/theoldpod/Artwork`, and a
    /// `LocalFolderWatcher` rooted at `LibraryLocation.defaultRoot()`.
    public init() throws {
        let root = try LibraryLocation.defaultRoot()
        container = try LibraryContainerFactory.make(storeURL: nil)
        artwork = try ArtworkStore(directory: Self.defaultArtworkDirectory())
        watcher = LocalFolderWatcher(root: root)
        libraryRoot = root
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
    }

    /// Idempotent: starts a task consuming `watcher.changes()` into the
    /// indexer. Calling this again while already running is a no-op.
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
