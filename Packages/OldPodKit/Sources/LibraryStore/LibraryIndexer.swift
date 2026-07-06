import CloudFiles
import Domain
import Foundation
import MetadataImport
import SwiftData

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
    private var artwork: ArtworkStore?

    public init(modelContainer: ModelContainer, artwork: ArtworkStore) {
        let modelContext = ModelContext(modelContainer)
        modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
        self.modelContainer = modelContainer
        self.artwork = artwork
    }

    public func apply(_ changes: [LibraryChange]) async {
        for change in changes {
            switch change {
            case let .upsert(file):
                await upsert(file)
            case let .remove(relativePath):
                remove(relativePath: relativePath)
            }
        }
        try? modelContext.save()
    }

    private func upsert(_ file: LibraryFile) async {
        let path = file.relativePath
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.relativePath == path })
        let existing = try? modelContext.fetch(descriptor).first

        if let existing,
           existing.fileModified == file.modified,
           existing.fileSize == file.size,
           existing.isDownloaded == file.isDownloaded
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
        let metadata = file.isDownloaded ? try? await MetadataReader.read(from: file.url) : nil

        var artworkID: String?
        if let data = metadata?.artwork {
            artworkID = try? artwork?.store(data)
        }

        let title = metadata?.title ?? fallbackTitle
        let artist = metadata?.artist ?? ""
        let album = metadata?.album ?? ""
        let duration = metadata?.duration ?? 0

        if let existing {
            existing.title = title
            existing.artist = artist
            existing.album = album
            existing.albumArtist = metadata?.albumArtist
            existing.trackNumber = metadata?.trackNumber
            existing.discNumber = metadata?.discNumber
            existing.year = metadata?.year
            existing.genre = metadata?.genre
            existing.duration = duration
            existing.fileSize = file.size
            existing.fileModified = file.modified
            existing.artworkID = artworkID
            existing.isDownloaded = file.isDownloaded
            // addedAt is preserved.
        } else {
            let track = Track(
                relativePath: path,
                title: title,
                artist: artist,
                album: album,
                albumArtist: metadata?.albumArtist,
                trackNumber: metadata?.trackNumber,
                discNumber: metadata?.discNumber,
                year: metadata?.year,
                genre: metadata?.genre,
                duration: duration,
                fileSize: file.size,
                fileModified: file.modified,
                artworkID: artworkID
            )
            track.isDownloaded = file.isDownloaded
            modelContext.insert(track)
        }
    }

    private func remove(relativePath: String) {
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.relativePath == relativePath })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
    }
}
