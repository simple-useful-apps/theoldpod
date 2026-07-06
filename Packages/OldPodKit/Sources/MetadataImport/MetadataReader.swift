import AVFoundation
import Foundation

/// Reads ID3 metadata and artwork from an audio file via `AVURLAsset`'s async
/// metadata API. Does not fall back to the filename on missing tags — that's
/// the indexer's job.
public enum MetadataReader {
    public static func read(from url: URL) async throws -> TrackMetadata {
        let asset = AVURLAsset(url: url)
        let (duration, commonItems) = try await asset.load(.duration, .commonMetadata)

        var title: String?
        var artist: String?
        var album: String?
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

        return TrackMetadata(
            title: title,
            artist: artist,
            album: album,
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
}
