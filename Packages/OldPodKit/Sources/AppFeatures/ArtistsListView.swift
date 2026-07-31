import Domain
import SwiftData
import SwiftUI

/// The Artists tab: every artist derived from the library's tracks, as a
/// plain list of name + "N albums · M songs" rows. Tapping a row pushes
/// `ArtistDetailView` for that artist.
public struct ArtistsListView: View {
    @Query private var tracks: [Track]

    private let coordinator: LibraryCoordinator

    public init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        let artists = LibraryGroups.artists(from: tracks)
        Group {
            if artists.isEmpty {
                ContentUnavailableView(
                    "No Artists Yet",
                    systemImage: "music.mic",
                    description: Text("Drop music files into\n\(coordinator.libraryRoot.path)")
                )
            } else {
                List(artists) { artist in
                    NavigationLink {
                        ArtistDetailView(artist: artist, coordinator: coordinator)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(artist.name)
                                .font(.body)
                            Text(summary(for: artist))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func summary(for artist: ArtistGroup) -> String {
        "\(LibraryText.albumCount(artist.albums.count)) · \(LibraryText.songCount(artist.trackCount))"
    }
}
