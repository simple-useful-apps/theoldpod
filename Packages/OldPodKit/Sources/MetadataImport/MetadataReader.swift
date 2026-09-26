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
        var trackTotal: Int?
        var discNumber: Int?
        var discTotal: Int?
        var year: Int?

        if let id3Items = try? await asset.loadMetadata(for: .id3Metadata) {
            for item in id3Items {
                switch item.identifier {
                case .id3MetadataBand:
                    albumArtist = try? await item.load(.stringValue)
                case .id3MetadataTrackNumber:
                    if let raw = try? await item.load(.stringValue) {
                        let pair = indexPair(in: raw)
                        trackNumber = pair.index
                        trackTotal = pair.total
                    }
                case .id3MetadataPartOfASet:
                    if let raw = try? await item.load(.stringValue) {
                        let pair = indexPair(in: raw)
                        discNumber = pair.index
                        discTotal = pair.total
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
                    if trackNumber == nil {
                        let pair = await iTunesIndex(from: item)
                        trackNumber = pair.index
                        trackTotal = pair.total
                    }
                case .iTunesMetadataDiscNumber:
                    if discNumber == nil {
                        let pair = await iTunesIndex(from: item)
                        discNumber = pair.index
                        discTotal = pair.total
                    }
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
            title: nonempty(title),
            artist: nonempty(artist),
            album: nonempty(album),
            albumArtist: nonempty(albumArtist),
            trackNumber: trackNumber,
            trackTotal: trackTotal,
            discNumber: discNumber,
            discTotal: discTotal,
            year: year,
            genre: genre,
            duration: duration.seconds.isFinite ? max(duration.seconds, 0) : 0,
            artwork: artwork
        )
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Parses a leading integer out of strings like "3/12" (track/disc number).
    private static func leadingInt(in string: String) -> Int? {
        let digits = string.prefix { $0.isNumber }
        return Int(digits)
    }

    private struct IndexPair {
        let index: Int?
        let total: Int?
    }

    /// Parses the item and optional total from ID3 values such as "3/12".
    private static func indexPair(in string: String) -> IndexPair {
        let components = string.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let index = components.first.flatMap { leadingInt(in: String($0)) }
        let total = components.count > 1 ? leadingInt(in: String(components[1])) : nil
        return IndexPair(index: index, total: total.flatMap { $0 > 0 ? $0 : nil })
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
    private static func iTunesIndex(from item: AVMetadataItem) async -> IndexPair {
        if let raw = try? await item.load(.stringValue), leadingInt(in: raw) != nil {
            return indexPair(in: raw)
        }
        guard let data = try? await item.load(.dataValue), data.count >= 4 else {
            return IndexPair(index: nil, total: nil)
        }
        let bytes = [UInt8](data)
        let value = Int(bytes[2]) << 8 | Int(bytes[3])
        let total = data.count >= 6 ? Int(bytes[4]) << 8 | Int(bytes[5]) : 0
        return IndexPair(index: value > 0 ? value : nil, total: total > 0 ? total : nil)
    }
}
