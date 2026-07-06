import DesignSystem
import Domain
import SwiftData
import SwiftUI

/// M1 minimal songs list: every `Track` in the library, sorted by title, with
/// no grouping/filtering — the tabbed Artists/Albums/Playlists UI lands in M3.
public struct SongsListView: View {
    @Query(sort: \Track.title) private var tracks: [Track]

    private let libraryRootPath: String

    public init(libraryRootPath: String) {
        self.libraryRootPath = libraryRootPath
    }

    public var body: some View {
        Group {
            if tracks.isEmpty {
                ContentUnavailableView(
                    "No Music Yet",
                    systemImage: "music.note",
                    description: Text("Drop MP3s into\n\(libraryRootPath)")
                )
            } else {
                List(tracks) { track in
                    SongRow(track: track)
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct SongRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            ArtworkPlaceholder()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            DurationText(track.duration)
        }
    }
}
