import AppFeatures
import DesignSystem
import Domain
import PlaybackEngine
import SwiftData
import SwiftUI

/// One playlist's ordered track list. A plain `List` with drag-to-reorder
/// rather than a sortable `Table`: manual order is the point of a playlist.
struct PlaylistDetailView: View {
    let playlist: Playlist
    let coordinator: LibraryCoordinator

    @Environment(\.modelContext) private var modelContext
    @Query private var availableTracks: [Track]
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var metadataEditor: MetadataEditorPresentation?

    init(playlist: Playlist, coordinator: LibraryCoordinator) {
        self.playlist = playlist
        self.coordinator = coordinator
        _availableTracks = .tracks(referencedBy: playlist)
    }

    var body: some View {
        let resolved = ResolvedPlaylist(playlist, availableTracks: availableTracks)
        VStack(alignment: .leading, spacing: 0) {
            header(resolved)
            Divider()
            if resolved.isEmpty {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note.list",
                    description: Text("Add songs from the library with Add to Playlist.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(resolved)
            }
        }
        .focusedSceneValue(\.getInfoAction, getInfoAction(resolved))
        .sheet(item: $metadataEditor) { request in
            MetadataEditorView(relativePath: request.relativePath, coordinator: coordinator)
        }
    }

    private func header(_ resolved: ResolvedPlaylist) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(LibraryText.summary(songs: resolved.rows.count, duration: resolved.totalDuration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            PlayShuffleButtons(
                isEnabled: !resolved.tracks.isEmpty,
                fullWidth: false,
                onPlay: { coordinator.play(resolved.tracks) },
                onShuffle: { coordinator.playShuffled(resolved.tracks) }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func list(_ resolved: ResolvedPlaylist) -> some View {
        List(selection: $selection) {
            ForEach(Array(resolved.rows.enumerated()), id: \.element.id) { position, row in
                PlaylistEntryRow(
                    row: row,
                    position: position,
                    isCurrent: coordinator.player.current?.relativePath == row.track?.relativePath
                )
                .padding(.vertical, 2)
            }
            .onMove { source, destination in
                PlaylistOps.moveEntries(from: source, to: destination, in: playlist, in: modelContext)
            }
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            Button("Play") { coordinator.play(resolved.tracks(matching: ids)) }
            Button("Play Next") { coordinator.playNext(resolved.tracks(matching: ids)) }
            Button("Add to Queue") { coordinator.enqueue(resolved.tracks(matching: ids)) }
            Divider()
            Button("Get Info") { openInfo(editableTrack(in: resolved, for: ids)) }
                .disabled(editableTrack(in: resolved, for: ids) == nil)
            Divider()
            Button("Remove from Playlist", role: .destructive) { removeEntries(resolved.offsets(of: ids), ids: ids) }
        } primaryAction: { ids in
            // Double-click plays the playable entries from the clicked one.
            if let clicked = ids.first, let index = resolved.playableIndex(of: clicked) {
                coordinator.play(resolved.tracks, startingAt: index)
            }
        }
        .onDeleteCommand {
            removeEntries(resolved.offsets(of: selection), ids: selection)
        }
    }

    private func getInfoAction(_ resolved: ResolvedPlaylist) -> (@MainActor () -> Void)? {
        guard let track = editableTrack(in: resolved, for: selection) else { return nil }
        return { openInfo(track) }
    }

    private func editableTrack(in resolved: ResolvedPlaylist, for ids: Set<PersistentIdentifier>) -> Track? {
        guard ids.count == 1, let track = resolved.tracks(matching: ids).first, track.isDownloaded else { return nil }
        return track
    }

    private func openInfo(_ track: Track?) {
        guard let track else { return }
        metadataEditor = MetadataEditorPresentation(relativePath: track.relativePath)
    }

    private func removeEntries(_ offsets: IndexSet, ids: Set<PersistentIdentifier>) {
        guard !offsets.isEmpty else { return }
        PlaylistOps.removeEntries(at: offsets, from: playlist, in: modelContext)
        selection.subtract(ids)
    }
}
