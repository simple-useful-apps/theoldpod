import DesignSystem
import SwiftUI

/// An artist's detail screen: their albums, sorted by year then title (per
/// `LibraryGroups.artists(from:)`), as small artwork rows. A compilation
/// they appear on lists with only their tracks and its album artist in the
/// subtitle. Tapping a row pushes `AlbumDetailView` for that album.
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
                            .lineLimit(2)
                        if let subtitle = subtitle(for: album) {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
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

    /// The year, plus the album's own artist when it isn't this one (a
    /// compilation appearance), e.g. "2010 · Various Artists".
    private func subtitle(for album: AlbumGroup) -> String? {
        var parts: [String] = []
        if let year = album.year { parts.append(String(year)) }
        if album.artistName.caseInsensitiveCompare(artist.name) != .orderedSame {
            parts.append(album.artistName)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
