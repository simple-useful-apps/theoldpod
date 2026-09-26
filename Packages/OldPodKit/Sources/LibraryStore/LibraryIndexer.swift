import CloudFiles
import Domain
import Foundation
import MetadataImport
import os
import SwiftData

public struct LibraryMetadataRefresh: Sendable {
    public let relativePath: String
    public let url: URL
    public let metadata: TrackMetadata
    public let fileSize: Int64
    public let fileModified: Date
    public let fileResourceIdentifier: String?

    public init(
        relativePath: String,
        url: URL,
        metadata: TrackMetadata,
        fileSize: Int64,
        fileModified: Date,
        fileResourceIdentifier: String?
    ) {
        self.relativePath = relativePath
        self.url = url
        self.metadata = metadata
        self.fileSize = fileSize
        self.fileModified = fileModified
        self.fileResourceIdentifier = fileResourceIdentifier
    }
}

/// Turns file-system diffs from a `LibraryFolderWatching` into `Track` rows.
/// All SwiftData work happens on this actor's own `ModelContext`.
///
/// `@ModelActor` synthesizes a `modelContainer`/`modelExecutor`-only
/// `init(modelContainer:)`. To also store an `ArtworkStore`, `artwork` is
/// declared as an `Optional` (so the macro's synthesized initializer, which
/// doesn't know about it, still satisfies definite initialization) and the
/// public initializer below sets up the macro's storage by hand alongside it.
@ModelActor
public actor LibraryIndexer {
    private static let logger = Logger(subsystem: "OldPodKit.LibraryStore", category: "LibraryIndexer")

    private var artwork: ArtworkStore?
    private var pathRevisions: [String: Int] = [:]

    public init(modelContainer: ModelContainer, artwork: ArtworkStore) {
        let modelContext = ModelContext(modelContainer)
        modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
        self.modelContainer = modelContainer
        self.artwork = artwork
    }

    /// `reconcilingFullSnapshot`: pass true when `changes` is a watcher's
    /// complete initial snapshot — every stored `Track` whose file is absent
    /// from it gets deleted, so the store can never outlive the folder it
    /// indexes (e.g. after a local → iCloud library-root switch).
    @discardableResult
    public func apply(_ changes: [LibraryChange], reconcilingFullSnapshot: Bool = false) async -> Bool {
        for change in changes {
            switch change {
            case let .upsert(file):
                let revision = bumpRevision(for: file.relativePath)
                await upsert(file, revision: revision)
            case let .remove(relativePath):
                _ = bumpRevision(for: relativePath)
                remove(relativePath: relativePath)
            }
        }
        if reconcilingFullSnapshot {
            let present = Set(changes.compactMap { change -> String? in
                if case let .upsert(file) = change { return file.relativePath }
                return nil
            })
            let all = (try? modelContext.fetch(FetchDescriptor<Track>())) ?? []
            for track in all where !present.contains(track.relativePath) {
                modelContext.delete(track)
            }
        }
        do {
            try modelContext.save()
        } catch {
            // Same policy as PlaylistOps: never crash on a failed save, but
            // leave a trail — a silently dropped batch looks like "my music
            // didn't import" with nothing to diagnose.
            Self.logger.error("Failed to save library index batch: \(error)")
            return false
        }
        return true
    }

    /// A Sendable snapshot used to confirm that a committed deletion batch
    /// really removed its targets. Call only after `apply` reports success.
    public func indexedRelativePaths() throws -> Set<String> {
        try Set(modelContext.fetch(FetchDescriptor<Track>()).map(\.relativePath))
    }

    /// Commits metadata prepared from currently existing files. Refetching
    /// each row after the caller's asynchronous read prevents a stale result
    /// from recreating a file that was deleted while metadata was loading.
    @discardableResult
    public func applyMetadataRefreshes(_ refreshes: [LibraryMetadataRefresh]) -> Set<String> {
        var updated: Set<String> = []
        for refresh in refreshes {
            guard currentFileVersion(at: refresh.url) == FileVersion(
                size: refresh.fileSize,
                modified: refresh.fileModified,
                resourceIdentifier: refresh.fileResourceIdentifier
            ) else { continue }
            let path = refresh.relativePath
            let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.relativePath == path })
            guard let track = try? modelContext.fetch(descriptor).first else { continue }
            applyAuthoritative(refresh.metadata, relativePath: path, to: track)
            track.fileSize = refresh.fileSize
            track.fileModified = refresh.fileModified
            track.isDownloaded = true
            updated.insert(path)
        }
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to save refreshed audio metadata: \(error)")
            return []
        }
        return updated
    }

    private func upsert(_ file: LibraryFile, revision: Int) async {
        let path = file.relativePath
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.relativePath == path })
        let existing = try? modelContext.fetch(descriptor).first

        if let existing,
           existing.fileModified == file.modified,
           existing.fileSize == file.size,
           existing.isDownloaded == file.isDownloaded,
           existing.duration > 0 || !file.isDownloaded
        {
            return
        }

        let filenameStem = (file.relativePath as NSString)
            .lastPathComponent as NSString
        let fallbackTitle = filenameStem.deletingPathExtension

        // Never force a download by reading it: an iCloud placeholder that
        // hasn't downloaded yet is indexed by filename alone, and picks up
        // its real metadata once `apply` sees it again with `isDownloaded`
        // flipped to `true`.
        let versionBeforeRead = file.isDownloaded ? currentFileVersion(at: file.url) : nil
        let metadata = file.isDownloaded ? try? await MetadataReader.read(from: file.url) : nil
        guard pathRevisions[path] == revision else { return }
        if file.isDownloaded {
            guard let versionBeforeRead,
                  versionBeforeRead == currentFileVersion(at: file.url),
                  versionBeforeRead.size == file.size,
                  versionBeforeRead.modified == file.modified
            else { return }
        }

        var artworkID: String?
        if let data = metadata?.artwork {
            artworkID = try? artwork?.store(data)
        }

        if let existing {
            if let metadata {
                applyAuthoritative(metadata, relativePath: path, to: existing)
            } else if file.isDownloaded {
                // A downloaded replacement is authoritative even if its
                // metadata is unreadable; retaining the prior file's title,
                // artwork, and duration would misrepresent the new bytes.
                existing.title = fallbackTitle
                existing.artist = ""
                existing.album = ""
                existing.albumArtist = nil
                existing.trackNumber = nil
                existing.discNumber = nil
                existing.year = nil
                existing.genre = nil
                existing.duration = 0
                existing.artworkID = nil
            }
            existing.fileSize = file.size
            existing.fileModified = file.modified
            if artworkID != nil { existing.artworkID = artworkID }
            existing.isDownloaded = file.isDownloaded
            // addedAt is preserved.
        } else {
            let track = Track(
                relativePath: path,
                title: metadata?.title ?? fallbackTitle,
                artist: metadata?.artist ?? "",
                album: metadata?.album ?? "",
                albumArtist: metadata?.albumArtist,
                trackNumber: metadata?.trackNumber,
                discNumber: metadata?.discNumber,
                year: metadata?.year,
                genre: metadata?.genre,
                duration: metadata?.duration ?? 0,
                fileSize: file.size,
                fileModified: file.modified,
                artworkID: artworkID
            )
            track.isDownloaded = file.isDownloaded
            modelContext.insert(track)
        }
    }

    /// A successful read is authoritative. In particular, clearing a tag in
    /// Get Info must clear the indexed value too; retaining a prior non-nil
    /// value here would make the edit appear to have failed. Failed reads and
    /// cloud placeholders never enter this method, so they continue to retain
    /// the last known metadata.
    private func applyAuthoritative(_ metadata: TrackMetadata, relativePath: String, to track: Track) {
        let filename = (relativePath as NSString).lastPathComponent as NSString
        track.title = metadata.title ?? filename.deletingPathExtension
        track.artist = metadata.artist ?? ""
        track.album = metadata.album ?? ""
        track.albumArtist = metadata.albumArtist
        track.trackNumber = metadata.trackNumber
        track.discNumber = metadata.discNumber
        track.year = metadata.year
        track.genre = metadata.genre
        if metadata.duration > 0, metadata.duration.isFinite { track.duration = metadata.duration }
        if let data = metadata.artwork, let artworkID = try? artwork?.store(data) {
            track.artworkID = artworkID
        } else {
            track.artworkID = nil
        }
    }

    private func remove(relativePath: String) {
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.relativePath == relativePath })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
    }

    private struct FileVersion: Equatable {
        let size: Int64
        let modified: Date
        let resourceIdentifier: String?
    }

    private func currentFileVersion(at url: URL) -> FileVersion? {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let size = values.fileSize,
              let modified = values.contentModificationDate
        else { return nil }
        return FileVersion(
            size: Int64(size),
            modified: modified,
            resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) }
        )
    }

    private func bumpRevision(for path: String) -> Int {
        let revision = (pathRevisions[path] ?? 0) &+ 1
        pathRevisions[path] = revision
        return revision
    }
}
