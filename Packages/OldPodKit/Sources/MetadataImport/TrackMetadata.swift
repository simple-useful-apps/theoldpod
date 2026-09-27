import Foundation

/// Metadata read from an audio file's embedded tags, prior to being merged with
/// filename/file-attribute fallbacks by the indexer.
public struct TrackMetadata: Sendable, Equatable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var trackNumber: Int?
    public var trackTotal: Int?
    public var discNumber: Int?
    public var discTotal: Int?
    public var year: Int?
    public var genre: String?
    public var duration: TimeInterval
    public var artwork: Data?

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        albumArtist: String? = nil,
        trackNumber: Int? = nil,
        trackTotal: Int? = nil,
        discNumber: Int? = nil,
        discTotal: Int? = nil,
        year: Int? = nil,
        genre: String? = nil,
        duration: TimeInterval,
        artwork: Data? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.trackNumber = trackNumber
        self.trackTotal = trackTotal
        self.discNumber = discNumber
        self.discTotal = discTotal
        self.year = year
        self.genre = genre
        self.duration = duration
        self.artwork = artwork
    }
}
