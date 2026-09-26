import Domain
import SwiftData
import SwiftUI

/// The Playlists tab: every user-created `Playlist`, oldest first. Tapping a
/// row pushes `PlaylistDetailView`. New playlists are created from the
/// toolbar "+"; existing ones can be renamed or deleted via swipe or
/// context menu.
struct PlaylistsListView: View {
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]

    private let coordinator: LibraryCoordinator

    @State private var isPresentingNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var searchText = ""

    @State private var rename: PlaylistRename?
    @State private var playlistPendingDelete: Playlist?

    init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }

    var body: some View {
        let filtered = playlists.filter { searchText.isEmpty || $0.name.localizedStandardContains(searchText) }
        Group {
            if playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "list.bullet",
                    description: Text("Tap + to make your first playlist.")
                )
            } else {
                List {
                    ForEach(filtered) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist, coordinator: coordinator)
                        } label: {
                            row(for: playlist)
                        }
                        .swipeActions(allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                playlistPendingDelete = playlist
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                rename = PlaylistRename(playlist)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                playlistPendingDelete = playlist
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search Playlists")
        .searchEmptyOverlay(isEmpty: !playlists.isEmpty && filtered.isEmpty, searchText: searchText)
        .refreshable { await coordinator.refreshLibrary() }
        .toolbar {
            ToolbarItem(placement: .automatic) { LibraryStatusButton(coordinator: coordinator) }
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
                coordinator.playlists.create(name: newPlaylistName)
            }
            Button("Cancel", role: .cancel) {}
        }
        .playlistRenameAlert($rename, coordinator: coordinator)
        .playlistDeleteConfirmation(for: $playlistPendingDelete, coordinator: coordinator)
    }

    private func row(for playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playlist.name)
                .font(.body)
            Text(LibraryText.songCount(playlist.entries.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
