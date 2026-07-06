import AppFeatures
import DesignSystem
import Domain
import PlaybackEngine
import SwiftData
import SwiftUI

/// One playlist's ordered track list. Unlike `SongsTableView`'s sortable
/// `Table`, this is a plain `List` with drag-to-reorder — manual order is the
/// whole point of a playlist, so there's no column sorting here.
///
/// Entries reference tracks by `relativePath` (see `PlaylistEntry`), so an
/// entry can go "dangling" if its file was removed from the library; those
/// render grayed out, italic, and aren't playable.
struct PlaylistDetailView: View {
    let playlist: Playlist
    let coordinator: LibraryCoordinator

    @Environment(\.modelContext) private var modelContext
    @Query private var allTracks: [Track]
    @State private var selection: Set<PersistentIdentifier> = []

    private var entries: [PlaylistEntry] {
        PlaylistOps.sortedEntries(of: playlist)
    }

    /// One fetch turned into a dictionary, so resolving every entry's track
    /// is a lookup rather than a per-row fetch (no N+1 query).
    private var tracksByPath: [String: Track] {
        Dictionary(uniqueKeysWithValues: allTracks.map { ($0.relativePath, $0) })
    }

    /// Entries that still resolve to a track, in playlist order — what's
    /// actually playable.
    private var resolvedEntries: [(entry: PlaylistEntry, track: Track)] {
        entries.compactMap { entry in
            guard let track = tracksByPath[entry.trackPath] else { return nil }
            return (entry, track)
        }
    }

    private var totalDuration: TimeInterval {
        resolvedEntries.reduce(0) { $0 + $1.track.duration }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Songs Yet",
                    systemImage: "music.note.list",
                    description: Text("Add songs from the Songs list's \u{201C}Add to Playlist\u{201D} menu.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("\(entries.count) song\(entries.count == 1 ? "" : "s") \u{00B7} \(DurationText.format(totalDuration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                playAll()
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .disabled(resolvedEntries.isEmpty)

            Button {
                shuffleAll()
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            .disabled(resolvedEntries.isEmpty)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                row(for: entry, position: index)
            }
            .onMove { source, destination in
                PlaylistOps.moveEntries(from: source, to: destination, in: playlist, in: modelContext)
            }
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            Button("Play") { play(ids) }
            Button("Play Next") { playNext(ids) }
            Button("Add to Queue") { addToQueue(ids) }
            Divider()
            Button("Remove from Playlist", role: .destructive) { removeEntries(ids) }
        } primaryAction: { ids in
            playFromClick(ids)
        }
        .onDeleteCommand {
            removeEntries(selection)
        }
    }

    private func row(for entry: PlaylistEntry, position: Int) -> some View {
        let track = tracksByPath[entry.trackPath]
        let isCurrent = track.map { coordinator.player.current?.relativePath == $0.relativePath } ?? false

        return HStack(spacing: 12) {
            Group {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.tint)
                } else {
                    Text("\(position + 1)")
                        .font(OldPodTypography.timeReadout())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, alignment: .trailing)

            if let track {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .lineLimit(1)
                    Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                DurationText(track.duration)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text((entry.trackPath as NSString).lastPathComponent)
                        .italic()
                        .lineLimit(1)
                    Text("File missing")
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func playAll() {
        let tracks = resolvedEntries.map(\.track)
        guard !tracks.isEmpty else { return }
        coordinator.player.play(coordinator.playableTracks(from: tracks), startingAt: 0)
    }

    private func shuffleAll() {
        let tracks = resolvedEntries.map(\.track)
        guard !tracks.isEmpty else { return }
        coordinator.player.play(coordinator.playableTracks(from: tracks), startingAt: 0)
        if !coordinator.player.isShuffled {
            coordinator.player.toggleShuffle()
        }
    }

    /// Double-click: play the resolved (playable) entries, starting at the
    /// clicked one. Clicking a dangling ("file missing") entry does nothing.
    private func playFromClick(_ ids: Set<PersistentIdentifier>) {
        guard let clickedID = ids.first,
              let index = resolvedEntries.firstIndex(where: { $0.entry.id == clickedID })
        else { return }
        let tracks = resolvedEntries.map(\.track)
        coordinator.player.play(coordinator.playableTracks(from: tracks), startingAt: index)
    }

    /// Context menu "Play": just the selected rows, in playlist order,
    /// skipping any dangling entries.
    private func play(_ ids: Set<PersistentIdentifier>) {
        let tracks = tracks(matching: ids)
        guard !tracks.isEmpty else { return }
        coordinator.player.play(coordinator.playableTracks(from: tracks), startingAt: 0)
    }

    private func playNext(_ ids: Set<PersistentIdentifier>) {
        let playables = coordinator.playableTracks(from: tracks(matching: ids))
        for playable in playables.reversed() {
            coordinator.player.playNext(playable)
        }
    }

    private func addToQueue(_ ids: Set<PersistentIdentifier>) {
        let playables = coordinator.playableTracks(from: tracks(matching: ids))
        for playable in playables {
            coordinator.player.append(playable)
        }
    }

    private func removeEntries(_ ids: Set<PersistentIdentifier>) {
        guard !ids.isEmpty else { return }
        let offsets = IndexSet(entries.enumerated().filter { ids.contains($0.element.id) }.map(\.offset))
        PlaylistOps.removeEntries(at: offsets, from: playlist, in: modelContext)
        selection.subtract(ids)
    }

    /// Resolves selected entry ids to tracks, preserving playlist order and
    /// skipping dangling entries.
    private func tracks(matching ids: Set<PersistentIdentifier>) -> [Track] {
        resolvedEntries.filter { ids.contains($0.entry.id) }.map(\.track)
    }
}
