import Domain
import SwiftUI

/// The song row context menu shared by `SongsListView` and `AlbumDetailView`.
/// The caller owns the state behind `onDelete` and `onAddToPlaylist`.
struct TrackContextMenuContent: View {
    let track: Track
    let coordinator: LibraryCoordinator
    let onDelete: () -> Void
    let onAddToPlaylist: () -> Void

    var body: some View {
        Button {
            coordinator.playNext([track])
        } label: {
            Label("Play Next", systemImage: "text.insert")
        }

        Button {
            coordinator.enqueue([track])
        } label: {
            Label("Add to Queue", systemImage: "text.append")
        }

        Button(action: onAddToPlaylist) {
            Label("Add to Playlist…", systemImage: "music.note.list")
        }

        Divider()
        Button(role: .destructive, action: onDelete) {
            Label("Delete Song…", systemImage: "trash")
        }
    }
}

public extension View {
    /// Presents `AddToPlaylistSheet` for `track` while it is set. Item-driven
    /// rather than `isPresented` plus an optional, which can present before
    /// the payload write is visible.
    func addToPlaylistSheet(for track: Binding<Track?>, coordinator: LibraryCoordinator) -> some View {
        sheet(item: track) { track in
            AddToPlaylistSheet(track: track, store: coordinator.playlists)
        }
    }
}
