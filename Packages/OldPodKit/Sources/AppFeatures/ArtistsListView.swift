import Domain
import SwiftData
import SwiftUI

/// The Artists tab: every artist derived from the library's tracks, as a
/// plain list of name + "N albums · M songs" rows. Tapping a row pushes
/// `ArtistDetailView` for that artist.
struct ArtistsListView: View {
    @Query private var tracks: [Track]
    @State private var searchText = ""

    private let coordinator: LibraryCoordinator

    init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }

    var body: some View {
        let artists = LibraryGroups.artists(from: tracks)
        let filtered = artists.filter { searchText.isEmpty || $0.name.localizedStandardContains(searchText) }
        Group {
            if artists.isEmpty {
                ContentUnavailableView(
                    "No Artists Yet",
                    systemImage: "music.mic",
                    description: Text("Drop music files into\n\(coordinator.libraryRoot.path)")
                )
            } else {
                List(filtered) { artist in
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
        .searchable(text: $searchText, prompt: "Search Artists")
        .searchEmptyOverlay(isEmpty: !artists.isEmpty && filtered.isEmpty, searchText: searchText)
        .refreshable { await coordinator.refreshLibrary() }
        .toolbar { ToolbarItem(placement: .automatic) { LibraryStatusButton(coordinator: coordinator) } }
    }

    private func summary(for artist: ArtistGroup) -> String {
        "\(LibraryText.albumCount(artist.albums.count)) · \(LibraryText.songCount(artist.trackCount))"
    }
}
