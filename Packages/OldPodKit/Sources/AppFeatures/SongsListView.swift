import DesignSystem
import Domain
import PlaybackEngine
import SwiftData
import SwiftUI

/// M1 minimal songs list: every `Track` in the library, sorted by title, with
/// no grouping — the tabbed Artists/Albums/Playlists UI lands in M3.
/// M2 adds tap-to-play: tapping a row plays the whole visible list starting
/// at that row. M3 adds a live, diacritic/case-insensitive search over
/// title/artist/album via `.searchable`.
public struct SongsListView: View {
    @Query(sort: \Track.title) private var tracks: [Track]
    @State private var searchText = ""

    private let coordinator: LibraryCoordinator

    public init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }

    /// `tracks` narrowed to those matching `searchText` in title, artist, or
    /// album — case and diacritic insensitive. Empty query means "no filter."
    private var filteredTracks: [Track] {
        guard !searchText.isEmpty else { return tracks }
        return tracks.filter { Self.matches($0, query: searchText) }
    }

    public var body: some View {
        Group {
            if tracks.isEmpty {
                ContentUnavailableView(
                    "No Music Yet",
                    systemImage: "music.note",
                    description: Text("Drop MP3s into\n\(coordinator.libraryRoot.path)")
                )
            } else if filteredTracks.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(Array(filteredTracks.enumerated()), id: \.element.persistentModelID) { index, track in
                        SongRow(
                            track: track,
                            isCurrent: coordinator.player.current?.relativePath == track.relativePath,
                            artworkDirectory: coordinator.artworkDirectory
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            coordinator.player.play(coordinator.playableTracks(from: filteredTracks), startingAt: index)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search Songs")
    }

    private static func matches(_ track: Track, query: String) -> Bool {
        let needle = Self.fold(query)
        return Self.fold(track.title).contains(needle)
            || Self.fold(track.artist).contains(needle)
            || Self.fold(track.album).contains(needle)
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

private struct SongRow: View {
    let track: Track
    let isCurrent: Bool
    let artworkDirectory: URL?

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(artworkID: track.artworkID, directory: artworkDirectory)
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
