import Domain
import SwiftUI

/// The Play Next / Add to Queue / Add to Playlist… menu shared by every song
/// row's context menu (`SongsListView`, `AlbumDetailView`). `onAddToPlaylist`
/// is left to the caller, which owns the `trackPendingPlaylistAdd` state that
/// drives its own `.addToPlaylistSheet(for:)`.
struct TrackContextMenuContent: View {
    let track: Track
    let coordinator: LibraryCoordinator
    let onDelete: (() -> Void)?
    let onAddToPlaylist: () -> Void

    init(
        track: Track,
        coordinator: LibraryCoordinator,
        onDelete: (() -> Void)? = nil,
        onAddToPlaylist: @escaping () -> Void
    ) {
        self.track = track
        self.coordinator = coordinator
        self.onDelete = onDelete
        self.onAddToPlaylist = onAddToPlaylist
    }

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

        if let onDelete {
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete Song…", systemImage: "trash")
            }
        }
    }
}

public extension View {
    /// Presents `AddToPlaylistSheet` for `track` once it's set. Item-driven,
    /// NOT `isPresented` + a separate optional: the `Bool` variant can
    /// evaluate its content closure before the payload write is visible,
    /// presenting an empty sheet (classic SwiftUI gotcha, found by UI
    /// testing).
    func addToPlaylistSheet(for track: Binding<Track?>, coordinator: LibraryCoordinator) -> some View {
        sheet(item: track) { track in
            AddToPlaylistSheet(track: track, store: coordinator.playlists)
        }
    }
}
