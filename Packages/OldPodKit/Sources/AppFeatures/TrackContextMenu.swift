import Domain
import SwiftUI

/// The Play Next / Add to Queue / Add to Playlist… menu shared by every song
/// row's context menu (`SongsListView`, `AlbumDetailView`). `onAddToPlaylist`
/// is left to the caller, which owns the `trackPendingPlaylistAdd` state that
/// drives its own `.addToPlaylistSheet(for:)`.
public struct TrackContextMenuContent: View {
    let track: Track
    let coordinator: LibraryCoordinator
    let onAddToPlaylist: () -> Void

    public init(track: Track, coordinator: LibraryCoordinator, onAddToPlaylist: @escaping () -> Void) {
        self.track = track
        self.coordinator = coordinator
        self.onAddToPlaylist = onAddToPlaylist
    }

    public var body: some View {
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
    }
}

public extension View {
    /// Presents `AddToPlaylistSheet` for `track` once it's set. Item-driven,
    /// NOT `isPresented` + a separate optional: the `Bool` variant can
    /// evaluate its content closure before the payload write is visible,
    /// presenting an empty sheet (classic SwiftUI gotcha, found by UI
    /// testing).
    func addToPlaylistSheet(for track: Binding<Track?>) -> some View {
        sheet(item: track) { track in
            AddToPlaylistSheet(track: track)
        }
    }
}
