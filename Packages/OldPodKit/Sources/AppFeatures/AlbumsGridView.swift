import DesignSystem
import Domain
import SwiftData
import SwiftUI

/// The Albums tab: every album derived from the library's tracks, as a
/// 2-column adaptive grid of artwork tiles. Tapping a tile pushes
/// `AlbumDetailView` for that album.
struct AlbumsGridView: View {
    @Query private var tracks: [Track]
    @State private var searchText = ""

    private let coordinator: LibraryCoordinator

    private static let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }

    var body: some View {
        let albums = LibraryGroups.albums(from: tracks)
        let filtered = albums.filter { searchText.isEmpty || $0.title.localizedStandardContains(searchText) || $0.artistName.localizedStandardContains(searchText) }
        Group {
            if albums.isEmpty {
                ContentUnavailableView(
                    "No Albums Yet",
                    systemImage: "square.stack",
                    description: Text("Drop music files into\n\(coordinator.libraryRoot.path)")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: Self.columns, spacing: 20) {
                        ForEach(filtered) { album in
                            NavigationLink {
                                AlbumDetailView(album: album, coordinator: coordinator)
                            } label: {
                                AlbumCell(album: album, artworkDirectory: coordinator.artworkDirectory)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search Albums")
        .overlay {
            if !albums.isEmpty, filtered.isEmpty { ContentUnavailableView.search(text: searchText) }
        }
        .refreshable { await coordinator.refreshLibrary() }
        .toolbar { ToolbarItem(placement: .automatic) { LibraryStatusButton(coordinator: coordinator) } }
    }
}

private struct AlbumCell: View {
    let album: AlbumGroup
    let artworkDirectory: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkImage(artworkID: album.artworkID, directory: artworkDirectory, cornerRadius: 8, pointSize: 180)
            Text(album.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(album.artistName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
