import Domain
import SwiftData
import SwiftUI

/// A sheet listing every playlist plus a "New Playlist…" row, for adding a
/// single `track` to one of them. Shared by song rows across the app
/// (`SongsListView`, `AlbumDetailView`) via their "Add to Playlist…" context
/// menu item.
struct AddToPlaylistSheet: View {
    let track: Track
    let store: PlaylistStore

    // Alphabetical, Finder-style (case/diacritic-insensitive, numbers in
    // numeric order), so a playlist is found by name, not by when it was made.
    @Query(sort: [SortDescriptor(\Playlist.name, comparator: .localizedStandard)]) private var playlists: [Playlist]
    @Environment(\.dismiss) private var dismiss

    @State private var isPresentingNewPlaylistAlert = false
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    newPlaylistName = ""
                    isPresentingNewPlaylistAlert = true
                } label: {
                    Label("New Playlist…", systemImage: "plus")
                }

                ForEach(playlists) { playlist in
                    Button {
                        store.add(track, to: playlist)
                        dismiss()
                    } label: {
                        Text(playlist.name)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .alert("New Playlist", isPresented: $isPresentingNewPlaylistAlert) {
                    TextField("Playlist Name", text: $newPlaylistName)
                    Button("Create") {
                        store.add(track, to: store.create(name: newPlaylistName))
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                }
        }
    }
}
