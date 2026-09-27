import Domain
import SwiftData
import SwiftUI

/// The Playlists tab: every user-created `Playlist`, alphabetically. Tapping a
/// row pushes `PlaylistDetailView`. New playlists are created from the
/// toolbar "+"; existing ones can be renamed or deleted via swipe or
/// context menu.
struct PlaylistsListView: View {
    /// Alphabetical, Finder-style (case/diacritic-insensitive, numbers in
    /// numeric order), so a playlist is found by name, not by when it was made.
    @Query(sort: [SortDescriptor(\Playlist.name, comparator: .localizedStandard)]) private var playlists: [Playlist]
    /// Every track, only to tell which playlist entries' files are missing.
    @Query private var tracks: [Track]

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
        let availablePaths = Set(tracks.map(\.relativePath))
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
                            row(for: playlist, availablePaths: availablePaths)
                        }
                        // Not a destructive-role button: that removes the row
                        // itself on tap, before the confirmation is answered.
                        .deleteSwipeAction("Delete") { playlistPendingDelete = playlist }
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

    private func row(for playlist: Playlist, availablePaths: Set<String>) -> some View {
        let playable = playlist.entries.count(where: { availablePaths.contains($0.trackPath) })
        return VStack(alignment: .leading, spacing: 2) {
            Text(playlist.name)
                .font(.body)
            Text(LibraryText.playlistSongCount(songs: playable, missing: playlist.entries.count - playable))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
