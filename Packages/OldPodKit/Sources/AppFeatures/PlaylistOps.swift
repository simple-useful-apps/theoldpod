import CloudFiles
import Domain
import Foundation
import os
import SwiftData

/// `@MainActor` operations over `Playlist`/`PlaylistEntry` for a given
/// `ModelContext`. `Playlist.entries` is declared `deleteRule: .cascade`, so
/// deleting a playlist removes its entries automatically.
@MainActor
public enum PlaylistOps {
    private static let logger = Logger(subsystem: "OldPodKit.AppFeatures", category: "PlaylistOps")

    /// Set once at startup by `LibraryCoordinator`; tests may set/clear it to
    /// observe (or suppress) the file-sync side effects of these mutations.
    /// `nil` (the default) means playlist files aren't wired up — used by
    /// tests that don't care about file sync at all.
    public static var fileSync: PlaylistFileSync?

    /// Creates and inserts a new playlist. `name` is normalized (see
    /// `normalizedName`); an empty result becomes "New Playlist".
    @discardableResult
    public static func create(name: String, in context: ModelContext) -> Playlist {
        let playlist = Playlist(name: normalizedName(name))
        context.insert(playlist)
        save(context)
        fileSync?.playlistChanged(playlist, in: context)
        return playlist
    }

    /// Renames `playlist`. `name` is normalized (see `normalizedName`); an
    /// empty result becomes "New Playlist".
    public static func rename(_ playlist: Playlist, to name: String, in context: ModelContext) {
        let oldName = playlist.name
        let newName = normalizedName(name)
        playlist.name = newName
        save(context)
        if newName != oldName {
            fileSync?.playlistRenamed(from: oldName, to: playlist, in: context)
        }
    }

    /// Deletes `playlist`; its entries cascade-delete via the relationship.
    public static func delete(_ playlist: Playlist, in context: ModelContext) {
        let name = playlist.name
        context.delete(playlist)
        save(context)
        fileSync?.playlistDeleted(named: name)
    }

    /// Appends a new entry referencing `track.relativePath` at the end of
    /// `playlist`. Duplicates are allowed — classic iTunes lets you add the
    /// same track to a playlist more than once.
    public static func add(_ track: Track, to playlist: Playlist, in context: ModelContext) {
        let nextPosition = (sortedEntries(of: playlist).last?.position ?? -1) + 1
        let entry = PlaylistEntry(position: nextPosition, trackPath: track.relativePath, playlist: playlist)
        context.insert(entry)
        save(context)
        fileSync?.playlistChanged(playlist, in: context)
    }

    /// Removes the entries at `offsets` (indices into `sortedEntries(of:)`)
    /// and renumbers the remaining entries' positions to `0..n`.
    public static func removeEntries(at offsets: IndexSet, from playlist: Playlist, in context: ModelContext) {
        var entries = sortedEntries(of: playlist)
        for index in offsets.sorted(by: >) {
            guard entries.indices.contains(index) else { continue }
            let entry = entries.remove(at: index)
            context.delete(entry)
        }
        renumber(entries)
        save(context)
        fileSync?.playlistChanged(playlist, in: context)
    }

    /// List-style reorder (matches `Array.move(fromOffsets:toOffset:)`
    /// semantics), renumbering positions `0..n` afterward.
    public static func moveEntries(
        from source: IndexSet, to destination: Int, in playlist: Playlist, in context: ModelContext
    ) {
        var entries = sortedEntries(of: playlist)
        entries.move(fromOffsets: source, toOffset: destination)
        renumber(entries)
        save(context)
        fileSync?.playlistChanged(playlist, in: context)
    }

    public static func sortedEntries(of playlist: Playlist) -> [PlaylistEntry] {
        playlist.entries.sorted { $0.position < $1.position }
    }

    /// Resolves `playlist`'s entries to `Track`s, in playlist order. Entries
    /// whose `trackPath` no longer matches a `Track` (the file was deleted)
    /// are skipped.
    public static func resolveTracks(of playlist: Playlist, in context: ModelContext) -> [Track] {
        sortedEntries(of: playlist).compactMap { entry in
            let path = entry.trackPath
            let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.relativePath == path })
            return try? context.fetch(descriptor).first
        }
    }

    // MARK: - Helpers

    /// Trims whitespace/newlines, then strips every "/" and ":" character —
    /// playlist names double as `.m3u8` filename stems for file sync (see
    /// `PlaylistFileSync`), so they must be valid path components on both
    /// platforms. An empty result becomes "New Playlist".
    private static func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.filter { $0 != "/" && $0 != ":" }
        return stripped.isEmpty ? "New Playlist" : stripped
    }

    private static func renumber(_ entries: [PlaylistEntry]) {
        for (index, entry) in entries.enumerated() {
            entry.position = index
        }
    }

    private static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            logger.warning("PlaylistOps: failed to save context: \(error, privacy: .public)")
        }
    }
}
