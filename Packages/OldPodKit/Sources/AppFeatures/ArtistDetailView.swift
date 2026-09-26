import DesignSystem
import SwiftUI

/// An artist's detail screen: their albums, sorted by year then title (per
/// `LibraryGroups.artists(from:)`), as small artwork rows. Tapping a row
/// pushes `AlbumDetailView` for that album.
struct ArtistDetailView: View {
    let artist: ArtistGroup
    let coordinator: LibraryCoordinator

    var body: some View {
        List(artist.albums) { album in
            NavigationLink {
                AlbumDetailView(album: album, coordinator: coordinator)
            } label: {
                HStack(spacing: 12) {
                    ArtworkImage(artworkID: album.artworkID, directory: coordinator.artworkDirectory, cornerRadius: 4, pointSize: 56)
                        .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(album.title)
                            .font(.body)
                        if let year = album.year {
                            Text(String(year))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(artist.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
