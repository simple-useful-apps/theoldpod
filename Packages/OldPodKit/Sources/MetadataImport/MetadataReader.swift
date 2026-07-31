import AVFoundation
import Foundation

/// Reads embedded metadata and artwork from an audio file via `AVURLAsset`'s
/// async metadata API. Does not fall back to the filename on missing tags — that's
/// the indexer's job.
public enum MetadataReader {
    public static func read(from url: URL) async throws -> TrackMetadata {
        let asset = AVURLAsset(url: url)
        let (duration, commonItems) = try await asset.load(.duration, .commonMetadata)

        var title: String?
        var artist: String?
        var album: String?
        var albumArtist: String?
        var genre: String?
        var artwork: Data?

        for item in commonItems {
            switch item.commonKey {
            case .commonKeyTitle:
                title = try? await item.load(.stringValue)
            case .commonKeyArtist:
                artist = try? await item.load(.stringValue)
            case .commonKeyAlbumName:
                album = try? await item.load(.stringValue)
            case .commonKeyType:
                genre = try? await item.load(.stringValue)
            case .commonKeyArtwork:
                artwork = try? await item.load(.dataValue)
            default:
                break
            }
        }

        var trackNumber: Int?
        var discNumber: Int?
        var year: Int?

        if let id3Items = try? await asset.loadMetadata(for: .id3Metadata) {
            for item in id3Items {
                switch item.identifier {
                case .id3MetadataTrackNumber:
                    if let raw = try? await item.load(.stringValue) {
                        trackNumber = leadingInt(in: raw)
                    }
                case .id3MetadataPartOfASet:
                    if let raw = try? await item.load(.stringValue) {
                        discNumber = leadingInt(in: raw)
                    }
                case .id3MetadataRecordingTime, .id3MetadataYear:
                    if year == nil, let raw = try? await item.load(.stringValue) {
                        year = leadingYear(in: raw)
                    }
                default:
                    break
                }
            }
        }

        // M4A files store fields such as genre, album artist, track/disc
        // numbers, and release year in the iTunes metadata keyspace. The
        // title/artist/album/artwork fields above usually arrive through
        // `commonMetadata`; only fill missing values here.
        if let iTunesItems = try? await asset.loadMetadata(for: .iTunesMetadata) {
            for item in iTunesItems {
                switch item.identifier {
                case .iTunesMetadataSongName:
                    if title == nil { title = try? await item.load(.stringValue) }
                case .iTunesMetadataArtist:
                    if artist == nil { artist = try? await item.load(.stringValue) }
                case .iTunesMetadataAlbum:
                    if album == nil { album = try? await item.load(.stringValue) }
                case .iTunesMetadataAlbumArtist:
                    if albumArtist == nil { albumArtist = try? await item.load(.stringValue) }
                case .iTunesMetadataCoverArt:
                    if artwork == nil { artwork = try? await item.load(.dataValue) }
                case .iTunesMetadataUserGenre:
                    if genre == nil { genre = try? await item.load(.stringValue) }
                case .iTunesMetadataTrackNumber:
                    if trackNumber == nil { trackNumber = await iTunesIndex(from: item) }
                case .iTunesMetadataDiscNumber:
                    if discNumber == nil { discNumber = await iTunesIndex(from: item) }
                case .iTunesMetadataReleaseDate:
                    if year == nil, let raw = try? await item.load(.stringValue) {
                        year = leadingYear(in: raw)
                    }
                default:
                    break
                }
            }
        }

        return TrackMetadata(
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            trackNumber: trackNumber,
            discNumber: discNumber,
            year: year,
            genre: genre,
            duration: duration.seconds,
            artwork: artwork
        )
    }

    /// Parses a leading integer out of strings like "3/12" (track/disc number).
    private static func leadingInt(in string: String) -> Int? {
        let digits = string.prefix { $0.isNumber }
        return Int(digits)
    }

    /// Parses a leading 4-digit year out of strings like "2001" (TYER) or
    /// "2001-05-01T00:00:00" (TDRC).
    private static func leadingYear(in string: String) -> Int? {
        let digits = string.prefix(4).filter(\.isNumber)
        guard digits.count == 4 else { return nil }
        return Int(digits)
    }

    /// iTunes `trkn`/`disk` atoms store the one-based item number in bytes
    /// 2...3 as an unsigned big-endian integer. Some encoders expose a string
    /// instead, so accept that representation first.
    private static func iTunesIndex(from item: AVMetadataItem) async -> Int? {
        if let raw = try? await item.load(.stringValue), let value = leadingInt(in: raw) {
            return value
        }
        guard let data = try? await item.load(.dataValue), data.count >= 4 else { return nil }
        let bytes = [UInt8](data)
        let value = Int(bytes[2]) << 8 | Int(bytes[3])
        return value > 0 ? value : nil
    }
}
