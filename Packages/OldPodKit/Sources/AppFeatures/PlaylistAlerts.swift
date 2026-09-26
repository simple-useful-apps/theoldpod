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
    func playlistRenameAlert(_ rename: Binding<PlaylistRename?>) -> some View {
        modifier(PlaylistRenameAlert(rename: rename))
    }

    /// Delete confirmation for `playlist`, presented while it is set. Deleting
    /// removes the playlist file on disk, so both platforms confirm first.
    func playlistDeleteConfirmation(
        for playlist: Binding<Playlist?>,
        onDeleted: @escaping (Playlist) -> Void = { _ in }
    ) -> some View {
        modifier(PlaylistDeleteConfirmation(playlist: playlist, onDeleted: onDeleted))
    }
}

private struct PlaylistRenameAlert: ViewModifier {
    @Binding var rename: PlaylistRename?
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.alert("Rename Playlist", isPresented: $rename.isPresent, presenting: rename) { rename in
            TextField("Playlist Name", text: name)
            Button("Save") {
                PlaylistOps.rename(rename.playlist, to: rename.name, in: modelContext)
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
    let onDeleted: (Playlist) -> Void
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete Playlist?",
            isPresented: $playlist.isPresent,
            titleVisibility: .visible,
            presenting: playlist
        ) { playlist in
            Button("Delete \u{201C}\(playlist.name)\u{201D}", role: .destructive) {
                PlaylistOps.delete(playlist, in: modelContext)
                onDeleted(playlist)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The playlist file will be removed from the library folder. This can\u{2019}t be undone.")
        }
    }
}
