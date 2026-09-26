import Domain
import SwiftData
import SwiftUI

/// A rename in progress: which playlist, and the name typed so far.
public struct PlaylistRename {
    public let playlist: Playlist
    public var name: String

    public init(_ playlist: Playlist) {
        self.playlist = playlist
        name = playlist.name
    }
}

public extension View {
    /// Rename alert for the playlist in `rename`, presented while it is set.
    func playlistRenameAlert(_ rename: Binding<PlaylistRename?>, coordinator: LibraryCoordinator) -> some View {
        modifier(PlaylistRenameAlert(rename: rename, playlists: coordinator.playlists))
    }

    /// Delete confirmation for `playlist`, presented while it is set. Deleting
    /// removes the playlist file on disk, so both platforms confirm first.
    func playlistDeleteConfirmation(
        for playlist: Binding<Playlist?>,
        coordinator: LibraryCoordinator,
        onDeleted: @escaping (Playlist) -> Void = { _ in }
    ) -> some View {
        modifier(PlaylistDeleteConfirmation(playlist: playlist, playlists: coordinator.playlists, onDeleted: onDeleted))
    }
}

private struct PlaylistRenameAlert: ViewModifier {
    @Binding var rename: PlaylistRename?
    let playlists: PlaylistStore

    func body(content: Content) -> some View {
        content.alert("Rename Playlist", isPresented: $rename.isPresent, presenting: rename) { rename in
            TextField("Playlist Name", text: name)
            Button("Save") {
                playlists.rename(rename.playlist, to: rename.name)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var name: Binding<String> {
        Binding(
            get: { rename?.name ?? "" },
            set: { rename?.name = $0 }
        )
    }
}

private struct PlaylistDeleteConfirmation: ViewModifier {
    @Binding var playlist: Playlist?
    let playlists: PlaylistStore
    let onDeleted: (Playlist) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete Playlist?",
            isPresented: $playlist.isPresent,
            titleVisibility: .visible,
            presenting: playlist
        ) { playlist in
            Button("Delete \u{201C}\(playlist.name)\u{201D}", role: .destructive) {
                playlists.delete(playlist)
                onDeleted(playlist)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The playlist file will be removed from the library folder. This can\u{2019}t be undone.")
        }
    }
}
