import Foundation
import SwiftData

/// A single audio file in the library, indexed from the file system. All fields
/// other than `relativePath` are derived from embedded metadata (or filename/file
/// attributes as a fallback) and can always be rebuilt by re-scanning the file.
@Model
public final class Track {
    @Attribute(.unique) public var relativePath: String
    public var title: String
    /// Empty when unknown; the UI maps "" to "Unknown Artist".
    public var artist: String
    /// Empty when unknown.
    public var album: String
    public var albumArtist: String?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var year: Int?
    public var genre: String?
    public var duration: TimeInterval
    public var fileSize: Int64
    public var fileModified: Date
    /// Key into `ArtworkStore`.
    public var artworkID: String?
    public var addedAt: Date
    /// `false` for an iCloud placeholder not yet downloaded to this device.
    /// Additive field (M5): existing stores migrate in with every row
    /// defaulting to `true`, matching the pre-M5 local-only behavior.
    public var isDownloaded: Bool = true

    public init(
        relativePath: String,
        title: String,
        artist: String = "",
        album: String = "",
        albumArtist: String? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        year: Int? = nil,
        genre: String? = nil,
        duration: TimeInterval,
        fileSize: Int64,
        fileModified: Date,
        artworkID: String? = nil,
        addedAt: Date = .now
    ) {
        self.relativePath = relativePath
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.year = year
        self.genre = genre
        self.duration = duration
        self.fileSize = fileSize
        self.fileModified = fileModified
        self.artworkID = artworkID
        self.addedAt = addedAt
    }

    public var displayArtist: String {
        artist.isEmpty ? "Unknown Artist" : artist
    }

    public var displayAlbum: String {
        album.isEmpty ? "Unknown Album" : album
    }
}
