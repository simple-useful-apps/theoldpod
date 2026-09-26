import DesignSystem
import Domain
import SwiftData
import SwiftUI

/// A playlist's entries matched against the tracks still in the library.
/// Entries reference files by path, so an entry whose file was removed stays
/// in the list (reorderable, removable) but has no track to play.
public struct ResolvedPlaylist {
    public struct Row: Identifiable {
        public let entry: PlaylistEntry
        public let track: Track?
        /// Position within `tracks` for a playable entry.
        public let playableIndex: Int?

        public var id: PersistentIdentifier {
            entry.persistentModelID
        }
    }

    public let rows: [Row]
    /// The playable tracks, in playlist order.
    public let tracks: [Track]

    @MainActor
    public init(_ playlist: Playlist, availableTracks: [Track]) {
        let byPath = Dictionary(availableTracks.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        var tracks: [Track] = []
        rows = playlist.sortedEntries.map { entry in
            guard let track = byPath[entry.trackPath] else {
                return Row(entry: entry, track: nil, playableIndex: nil)
            }
            tracks.append(track)
            return Row(entry: entry, track: track, playableIndex: tracks.count - 1)
        }
        self.tracks = tracks
    }

    public var isEmpty: Bool {
        rows.isEmpty
    }

    public var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }

    /// Playable tracks among the entries `ids`, in playlist order.
    public func tracks(matching ids: Set<PersistentIdentifier>) -> [Track] {
        rows.filter { ids.contains($0.id) }.compactMap(\.track)
    }

    public func playableIndex(of id: PersistentIdentifier) -> Int? {
        rows.first { $0.id == id }?.playableIndex
    }

    /// Offsets into the entry list for the entries `ids`.
    public func offsets(of ids: Set<PersistentIdentifier>) -> IndexSet {
        IndexSet(rows.enumerated().filter { ids.contains($0.element.id) }.map(\.offset))
    }
}

public extension Query<Track, [Track]> {
    /// Only the tracks `playlist` references, so resolving every entry is one
    /// fetch rather than a query per row.
    @MainActor
    static func tracks(referencedBy playlist: Playlist) -> Query<Track, [Track]> {
        let paths = Set(playlist.sortedEntries.map(\.trackPath))
        return Query(filter: #Predicate<Track> { paths.contains($0.relativePath) })
    }
}

/// One playlist row: position or now-playing marker, title and artist, and
/// duration. An entry with no track reads as "File missing".
public struct PlaylistEntryRow: View {
    private let row: ResolvedPlaylist.Row
    private let position: Int
    private let isCurrent: Bool

    public init(row: ResolvedPlaylist.Row, position: Int, isCurrent: Bool) {
        self.row = row
        self.position = position
        self.isCurrent = isCurrent
    }

    public var body: some View {
        HStack(spacing: 12) {
            Group {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.tint)
                } else {
                    Text("\(position + 1)")
                        .font(OldPodTypography.timeReadout())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, alignment: .trailing)

            if let track = row.track {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.body)
                        .lineLimit(1)
                    Text(track.displayArtist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                DurationText(track.duration)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text((row.entry.trackPath as NSString).lastPathComponent)
                        .font(.body)
                        .italic()
                        .lineLimit(1)
                    Text("File missing")
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}
