import Domain
import SwiftData
import SwiftUI

/// The Playlists tab: every user-created `Playlist`, oldest first. Tapping a
/// row pushes `PlaylistDetailView`. New playlists are created from the
/// toolbar "+"; existing ones can be renamed or deleted via swipe or
/// context menu.
public struct PlaylistsListView: View {
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
    @Environment(\.modelContext) private var modelContext

    private let coordinator: LibraryCoordinator

    @State private var isPresentingNewPlaylistAlert = false
    @State private var newPlaylistName = ""

    @State private var renamingPlaylist: Playlist?
    @State private var renameText = ""

    public init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        Group {
            if playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "list.bullet",
                    description: Text("Tap + to make your first playlist.")
                )
            } else {
                List {
                    ForEach(playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist, coordinator: coordinator)
                        } label: {
                            row(for: playlist)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                PlaylistOps.delete(playlist, in: modelContext)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                renameText = playlist.name
                                renamingPlaylist = playlist
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                PlaylistOps.delete(playlist, in: modelContext)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newPlaylistName = ""
                    isPresentingNewPlaylistAlert = true
                } label: {
                    Label("New Playlist", systemImage: "plus")
                }
            }
        }
        .alert("New Playlist", isPresented: $isPresentingNewPlaylistAlert) {
            TextField("Playlist Name", text: $newPlaylistName)
            Button("Create") {
                PlaylistOps.create(name: newPlaylistName, in: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Playlist", isPresented: renamingPlaylistBinding) {
            TextField("Playlist Name", text: $renameText)
            Button("Save") {
                if let renamingPlaylist {
                    PlaylistOps.rename(renamingPlaylist, to: renameText, in: modelContext)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Bridges the optional `renamingPlaylist` (which the alert needs to
    /// know *which* playlist to rename on save) to the `Bool` binding
    /// `.alert(_:isPresented:)` requires.
    private var renamingPlaylistBinding: Binding<Bool> {
        Binding(
            get: { renamingPlaylist != nil },
            set: { isPresented in if !isPresented { renamingPlaylist = nil } }
        )
    }

    private func row(for playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playlist.name)
                .font(.body)
            Text(playlist.entries.count == 1 ? "1 song" : "\(playlist.entries.count) songs")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
