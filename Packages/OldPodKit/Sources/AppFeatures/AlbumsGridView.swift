import DesignSystem
import Domain
import SwiftData
import SwiftUI

/// The Albums tab: every album derived from the library's tracks, as a
/// 2-column adaptive grid of artwork tiles. Tapping a tile pushes
/// `AlbumDetailView` for that album.
public struct AlbumsGridView: View {
    @Query private var tracks: [Track]

    private let coordinator: LibraryCoordinator

    private static let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    public init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        let albums = LibraryGroups.albums(from: tracks)
        Group {
            if albums.isEmpty {
                ContentUnavailableView(
                    "No Albums Yet",
                    systemImage: "square.stack",
                    description: Text("Drop MP3s into\n\(coordinator.libraryRoot.path)")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: Self.columns, spacing: 20) {
                        ForEach(albums) { album in
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
    }
}

private struct AlbumCell: View {
    let album: AlbumGroup
    let artworkDirectory: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkImage(artworkID: album.artworkID, directory: artworkDirectory, cornerRadius: 8)
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
