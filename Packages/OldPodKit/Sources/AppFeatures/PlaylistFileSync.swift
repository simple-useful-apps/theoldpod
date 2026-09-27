import CloudFiles
import Domain
import Foundation
import os
import SwiftData

/// Keeps `.m3u8` files under `<libraryRoot>/Playlists` and the SwiftData
/// `Playlist`/`PlaylistEntry` rows in sync, in both directions: `PlaylistStore`
/// calls the `playlistChanged`/`playlistDeleted`/`playlistRenamed` hooks
/// after every mutation to push SwiftData -> files, and `reconcile()` (run at
/// startup and on every folder-watcher event) pulls files -> SwiftData so
/// external edits (Finder, another app, iCloud sync from another device)
/// take effect. Files are the source of truth; SwiftData is always
/// rebuildable from them.
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

    /// One-time migration for playlists created before playlist files
    /// existed: writes a file for every playlist that has none (existing
    /// files win), then reconciles. Without it, `reconcile()` would delete
    /// every pre-file playlist on first launch.
    public func migrateAndReconcile() {
        if !defaults.bool(forKey: Self.exportedV1DefaultsKey) {
            let context = container.mainContext
            guard (try? store.ensureDirectoryExists()) != nil,
                  let files = try? store.readAll() else { return }
            let existingFileNames = Set(files.keys)
            let playlists = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []
            for playlist in playlists where !existingFileNames.contains(playlist.name) {
                guard store.write(name: playlist.name, entries: serialize(playlist, in: context)) else { return }
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

    /// Makes SwiftData match the files on disk: playlists without a file are
    /// deleted, files without a playlist create one, and differing entries
    /// are replaced wholesale. Titles and durations in the file are display
    /// hints only; the `Track` rows are authoritative.
    ///
    /// Never writes files, so a reconcile triggered by our own write is a
    /// no-op rather than a write-back loop. A file renamed outside the app
    /// therefore reads as delete-then-create.
    public func reconcile() {
        let context = container.mainContext
        // An unavailable iCloud file or directory is not an empty library.
        // Keep the last good index until a complete read succeeds.
        guard let files = try? store.readAll() else { return }
        let playlists = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []

        for playlist in playlists where files[playlist.name] == nil {
            context.delete(playlist)
        }

        // Older versions allowed duplicate names. Reconcile that legacy
        // index to one row per file; new mutations use collision-free names.
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
                let currentPaths = existing.sortedEntries.map(\.trackPath)
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

    // MARK: - Write hooks (called by `PlaylistStore` after each mutation)

    func playlistChanged(_ playlist: Playlist, in context: ModelContext) {
        store.write(name: playlist.name, entries: serialize(playlist, in: context))
    }

    func playlistDeleted(named name: String) {
        store.delete(name: name)
    }

    func playlistRenamed(from oldName: String, to playlist: Playlist, in context: ModelContext) {
        guard store.write(name: playlist.name, entries: serialize(playlist, in: context)) else {
            playlist.name = oldName
            save(context)
            return
        }
        if oldName.caseInsensitiveCompare(playlist.name) != .orderedSame {
            store.delete(name: oldName)
        }
    }

    // MARK: - Helpers

    /// Every entry, including ones whose track is gone, so the file
    /// round-trips completely.
    private func serialize(_ playlist: Playlist, in context: ModelContext) -> [PlaylistFileEntry] {
        playlist.sortedEntries.map { entry in
            let path = entry.trackPath
            let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.relativePath == path })
            if let track = try? context.fetch(descriptor).first {
                let duration = track.duration
                let seconds = duration.isFinite && duration >= 0 && duration < Double(Int.max)
                    ? Int(duration.rounded()) : -1
                return PlaylistFileEntry(trackPath: path, title: track.title, seconds: seconds)
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
