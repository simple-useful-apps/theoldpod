import CloudFiles
import Domain
import Foundation
import os
import SwiftData

/// Every playlist mutation: it updates the SwiftData rows and mirrors each
/// change to the playlist's `.m3u8` file, so the files stay the source of
/// truth. `Playlist.entries` cascade-deletes, so removing a playlist removes
/// its entries.
@MainActor
public final class PlaylistStore {
    private let context: ModelContext
    private let files: PlaylistFileSync?

    private static let logger = Logger(subsystem: "OldPodKit.AppFeatures", category: "PlaylistStore")

    /// `files` is nil where playlist files are not wired up, such as tests
    /// that only care about the rows.
    public init(context: ModelContext, files: PlaylistFileSync? = nil) {
        self.context = context
        self.files = files
    }

    /// Creates a playlist with a safe, unique filename. Empty names become
    /// "New Playlist"; collisions receive a numbered suffix.
    @discardableResult
    public func create(name: String) -> Playlist {
        let playlist = Playlist(name: uniqueName(name))
        context.insert(playlist)
        save()
        files?.playlistChanged(playlist, in: context)
        return playlist
    }

    /// Renames without overwriting another playlist's file.
    public func rename(_ playlist: Playlist, to name: String) {
        let oldName = playlist.name
        playlist.name = uniqueName(name, excluding: playlist)
        save()
        if playlist.name != oldName {
            files?.playlistRenamed(from: oldName, to: playlist, in: context)
        }
    }

    public func delete(_ playlist: Playlist) {
        let name = playlist.name
        context.delete(playlist)
        save()
        files?.playlistDeleted(named: name)
    }

    /// Appends `track` to the end. Duplicates are allowed, as in classic iTunes.
    public func add(_ track: Track, to playlist: Playlist) {
        let nextPosition = (playlist.sortedEntries.last?.position ?? -1) + 1
        context.insert(PlaylistEntry(position: nextPosition, trackPath: track.relativePath, playlist: playlist))
        save()
        files?.playlistChanged(playlist, in: context)
    }

    /// Removes the entries at `offsets` (indices into `sortedEntries`) and
    /// renumbers the rest from zero.
    public func removeEntries(at offsets: IndexSet, from playlist: Playlist) {
        var entries = playlist.sortedEntries
        for index in offsets.sorted(by: >) where entries.indices.contains(index) {
            context.delete(entries.remove(at: index))
        }
        renumber(entries)
        save()
        files?.playlistChanged(playlist, in: context)
    }

    /// List-style reorder, matching `Array.move(fromOffsets:toOffset:)`.
    public func moveEntries(from source: IndexSet, to destination: Int, in playlist: Playlist) {
        var entries = playlist.sortedEntries
        entries.move(fromOffsets: source, toOffset: destination)
        renumber(entries)
        save()
        files?.playlistChanged(playlist, in: context)
    }

    /// The playlist's tracks in order, skipping entries whose file is gone.
    public func resolveTracks(of playlist: Playlist) -> [Track] {
        playlist.sortedEntries.compactMap { entry in
            let path = entry.trackPath
            let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.relativePath == path })
            return try? context.fetch(descriptor).first
        }
    }

    /// Names are file identities: never reuse another playlist's name, even
    /// differing only in case, since Apple file systems fold case.
    private func uniqueName(_ name: String, excluding playlist: Playlist? = nil) -> String {
        let base = PlaylistFileFormat.sanitizedFilename(for: name)
        let playlists = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []
        let occupied = Set(playlists.filter { $0 !== playlist }.map { $0.name.lowercased() })
        var candidate = base
        var suffix = 2
        while occupied.contains(candidate.lowercased()) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func renumber(_ entries: [PlaylistEntry]) {
        for (index, entry) in entries.enumerated() {
            entry.position = index
        }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Self.logger.warning("Failed to save playlist change: \(error, privacy: .public)")
        }
    }
}
