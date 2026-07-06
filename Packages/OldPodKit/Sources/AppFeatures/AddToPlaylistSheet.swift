import Domain
import SwiftData
import SwiftUI

/// A sheet listing every playlist plus a "New Playlist…" row, for adding a
/// single `track` to one of them. Shared by song rows across the app
/// (`SongsListView`, `AlbumDetailView`) via their "Add to Playlist…" context
/// menu item.
public struct AddToPlaylistSheet: View {
    let track: Track

    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isPresentingNewPlaylistAlert = false
    @State private var newPlaylistName = ""

    public init(track: Track) {
        self.track = track
    }

    public var body: some View {
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
                        PlaylistOps.add(track, to: playlist, in: modelContext)
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
                        let playlist = PlaylistOps.create(name: newPlaylistName, in: modelContext)
                        PlaylistOps.add(track, to: playlist, in: modelContext)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                }
        }
    }
}
