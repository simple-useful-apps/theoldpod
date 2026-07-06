import DesignSystem
import Domain
import PlaybackEngine
import SwiftData
import SwiftUI

/// M1 minimal songs list: every `Track` in the library, sorted by title, with
/// no grouping/filtering — the tabbed Artists/Albums/Playlists UI lands in M3.
/// M2 adds tap-to-play: tapping a row plays the whole visible list starting
/// at that row.
public struct SongsListView: View {
    @Query(sort: \Track.title) private var tracks: [Track]

    private let coordinator: LibraryCoordinator

    public init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        Group {
            if tracks.isEmpty {
                ContentUnavailableView(
                    "No Music Yet",
                    systemImage: "music.note",
                    description: Text("Drop MP3s into\n\(coordinator.libraryRoot.path)")
                )
            } else {
                List {
                    ForEach(Array(tracks.enumerated()), id: \.element.persistentModelID) { index, track in
                        SongRow(
                            track: track,
                            isCurrent: coordinator.player.current?.relativePath == track.relativePath
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            coordinator.player.play(coordinator.playableTracks(from: tracks), startingAt: index)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct SongRow: View {
    let track: Track
    let isCurrent: Bool

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

            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
            } else {
                DurationText(track.duration)
            }
        }
    }
}
