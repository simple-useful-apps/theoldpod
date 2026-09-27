import DesignSystem
import Domain
import PlaybackEngine
import SwiftData
import SwiftUI

/// A single playlist's screen: entries in playlist order, with Play and
/// Shuffle over the entries that still have a file.
struct PlaylistDetailView: View {
    let playlist: Playlist
    let coordinator: LibraryCoordinator

    @Query private var availableTracks: [Track]

    init(playlist: Playlist, coordinator: LibraryCoordinator) {
        self.playlist = playlist
        self.coordinator = coordinator
        _availableTracks = .tracks(referencedBy: playlist)
    }

    var body: some View {
        let resolved = ResolvedPlaylist(playlist, availableTracks: availableTracks)
        Group {
            if resolved.isEmpty {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note.list",
                    description: Text("Add songs from the library with Add to Playlist.")
                )
            } else {
                List {
                    Section {
                        header(resolved)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                    Section {
                        ForEach(Array(resolved.rows.enumerated()), id: \.element.id) { position, row in
                            PlaylistEntryRow(
                                row: row,
                                position: position,
                                isCurrent: coordinator.player.current?.relativePath == row.track?.relativePath
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let index = row.playableIndex {
                                    coordinator.play(resolved.tracks, startingAt: index)
                                }
                            }
                        }
                        .onMove { source, destination in
                            coordinator.playlists.moveEntries(from: source, to: destination, in: playlist)
                        }
                        .onDelete { offsets in
                            coordinator.playlists.removeEntries(at: offsets, from: playlist)
                        }
                    }
                }
                .listStyle(.plain)
                #if os(iOS)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) { EditButton() }
                    }
                #endif
            }
        }
        .navigationTitle(playlist.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func header(_ resolved: ResolvedPlaylist) -> some View {
        VStack(spacing: 12) {
            Text(LibraryText.playlistSummary(
                songs: resolved.tracks.count,
                missing: resolved.rows.count - resolved.tracks.count,
                duration: resolved.totalDuration
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            PlayShuffleButtons(
                isEnabled: !resolved.tracks.isEmpty,
                onPlay: { coordinator.play(resolved.tracks) },
                onShuffle: { coordinator.playShuffled(resolved.tracks) }
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 24)
    }
}
