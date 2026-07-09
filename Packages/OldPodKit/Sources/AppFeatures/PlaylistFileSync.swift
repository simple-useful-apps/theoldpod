import CloudFiles
import Domain
import Foundation
import os
import SwiftData

/// Keeps `.m3u8` files under `<libraryRoot>/Playlists` and the SwiftData
/// `Playlist`/`PlaylistEntry` rows in sync, in both directions: `PlaylistOps`
/// calls the `playlistChanged`/`playlistDeleted`/`playlistRenamed` hooks
/// after every mutation to push SwiftData -> files, and `reconcile()` (run at
/// startup and on every folder-watcher event) pulls files -> SwiftData so
/// external edits (Finder, another app, iCloud sync from another device)
/// take effect. Files are the source of truth per `CLAUDE.md` — SwiftData is
/// always rebuildable from them.
@MainActor
public final class PlaylistFileSync {
    private let store: PlaylistFileStore
    private let container: ModelContainer
    private let defaults: UserDefaults
    private let watcher: PlaylistFolderWatcher
    private var watchTask: Task<Void, Never>?

    private static let logger = Logger(subsystem: "OldPodKit.AppFeatures", category: "PlaylistFileSync")
    private static let exportedV1DefaultsKey = "PlaylistFileSync.exportedV1"

    public init(store: PlaylistFileStore, container: ModelContainer, defaults: UserDefaults = .standard) {
        self.store = store
        self.container = container
        self.defaults = defaults
        watcher = PlaylistFolderWatcher(directory: store.directory)
    }

    /// One-time migration for users who created playlists before playlist
    /// files existed: exports every SwiftData playlist to a file, unless a
    /// file with that name is already there (files win — this only fills in
    /// gaps, it never overwrites). Guarded by a `UserDefaults` flag so it
    /// runs exactly once per install; after that, files are the sole truth
    /// and `reconcile()` would otherwise delete a v1 user's playlists on
    /// this build's first launch, since none of them have files yet.
    public func migrateAndReconcile() {
        if !defaults.bool(forKey: Self.exportedV1DefaultsKey) {
            let context = container.mainContext
            let existingFileNames = Set(store.readAll().keys)
            let playlists = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []
            for playlist in playlists where !existingFileNames.contains(playlist.name) {
                store.write(name: playlist.name, entries: serialize(playlist, in: context))
            }
            defaults.set(true, forKey: Self.exportedV1DefaultsKey)
        }
        reconcile()
    }

    /// Idempotent: starts a task that reconciles on every debounced folder
    /// event. Calling this again while already running is a no-op.
    public func startWatching() {
        guard watchTask == nil else { return }
        let watcher = watcher
        watchTask = Task { [weak self] in
            for await _ in watcher.events() {
                self?.reconcile()
            }
        }
    }

    public func stop() {
        watcher.stop()
        watchTask?.cancel()
        watchTask = nil
    }

    /// Makes SwiftData match the files on disk: playlists whose name no
    /// longer has a file are deleted; files with no matching playlist create
    /// one; files whose entries differ from the matching playlist's replace
    /// that playlist's entries wholesale, renumbered `0..n`. Titles/seconds
    /// stored in the file are advisory display data only — never trusted on
    /// import, since the `Track` rows are the real source for those.
    ///
    /// Deliberately performs no file writes, so a reconcile triggered by the
    /// watcher picking up our *own* write is a no-op rather than a
    /// write-back loop. One consequence: renaming a file externally (rather
    /// than through the app) reads as delete-then-create — the "renamed"
    /// playlist gets a new `createdAt` and loses continuity with the old
    /// one. That's accepted; the on-disk filename is the only identity a
    /// plain file rename can express.
    public func reconcile() {
        let context = container.mainContext
        let files = store.readAll()
        let playlists = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []

        for playlist in playlists where files[playlist.name] == nil {
            context.delete(playlist)
        }

        // Nothing stops the app from holding two playlists with the same name
        // (both platforms' "New Playlist" actions create the same default name
        // every time) — but one name maps to one file, and one file can only
        // describe one playlist. Keep the first, delete the extras: they merge,
        // which is what "files are the truth" demands.
        var survivingByName: [String: Playlist] = [:]
        for playlist in playlists where files[playlist.name] != nil {
            if survivingByName[playlist.name] == nil {
                survivingByName[playlist.name] = playlist
            } else {
                context.delete(playlist)
            }
        }

        for (name, fileEntries) in files {
            let trackPaths = fileEntries.map(\.trackPath)
            if let existing = survivingByName[name] {
                let currentPaths = PlaylistOps.sortedEntries(of: existing).map(\.trackPath)
                guard currentPaths != trackPaths else { continue }
                for entry in existing.entries {
                    context.delete(entry)
                }
                for (index, path) in trackPaths.enumerated() {
                    context.insert(PlaylistEntry(position: index, trackPath: path, playlist: existing))
                }
            } else {
                let playlist = Playlist(name: name)
                context.insert(playlist)
                for (index, path) in trackPaths.enumerated() {
                    context.insert(PlaylistEntry(position: index, trackPath: path, playlist: playlist))
                }
            }
        }

        save(context)
    }

    // MARK: - Write hooks (called by `PlaylistOps` after each mutation)

    func playlistChanged(_ playlist: Playlist, in context: ModelContext) {
        store.write(name: playlist.name, entries: serialize(playlist, in: context))
    }

    func playlistDeleted(named name: String) {
        store.delete(name: name)
    }

    func playlistRenamed(from oldName: String, to playlist: Playlist, in context: ModelContext) {
        store.delete(name: oldName)
        store.write(name: playlist.name, entries: serialize(playlist, in: context))
    }

    // MARK: - Helpers

    /// Resolves `playlist`'s entries to `PlaylistFileEntry` values for
    /// export. Unlike `PlaylistOps.resolveTracks`, dangling entries (no
    /// matching `Track`) are kept rather than skipped, since the file format
    /// needs to preserve every entry to round-trip correctly.
    private func serialize(_ playlist: Playlist, in context: ModelContext) -> [PlaylistFileEntry] {
        PlaylistOps.sortedEntries(of: playlist).map { entry in
            let path = entry.trackPath
            let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.relativePath == path })
            if let track = try? context.fetch(descriptor).first {
                return PlaylistFileEntry(trackPath: path, title: track.title, seconds: Int(track.duration.rounded()))
            }
            return PlaylistFileEntry(trackPath: path, title: stem(of: path), seconds: -1)
        }
    }

    private func stem(of path: String) -> String {
        let lastComponent = (path as NSString).lastPathComponent
        return (lastComponent as NSString).deletingPathExtension
    }

    private func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            Self.logger.warning("PlaylistFileSync: failed to save context: \(error, privacy: .public)")
        }
    }
}
