import DesignSystem
import Domain
import PlaybackEngine
import SwiftData
import SwiftUI

/// A single playlist's detail screen: entries in playlist order, each
/// resolved to its `Track` by `trackPath`. Entries whose file has since
/// disappeared render as dangling rows rather than being silently dropped,
/// so reordering/removal still lines up with what the user sees. Play and
/// Shuffle only ever consider resolvable tracks.
public struct PlaylistDetailView: View {
    let playlist: Playlist
    let coordinator: LibraryCoordinator

    // One fetch of every `Track`, turned into a `relativePath -> Track`
    // dictionary below, so resolving each entry never issues its own query.
    @Query private var allTracks: [Track]
    @Environment(\.modelContext) private var modelContext

    public init(playlist: Playlist, coordinator: LibraryCoordinator) {
        self.playlist = playlist
        self.coordinator = coordinator
    }

    private var entries: [PlaylistEntry] {
        PlaylistOps.sortedEntries(of: playlist)
    }

    private var tracksByPath: [String: Track] {
        Dictionary(uniqueKeysWithValues: allTracks.map { ($0.relativePath, $0) })
    }

    /// Each entry paired with its resolved `Track` (`nil` if dangling) and,
    /// for resolvable entries, that track's index within `resolvedTracks` —
    /// the index tapping it should start playback at.
    private struct Row: Identifiable {
        let entry: PlaylistEntry
        let track: Track?
        let resolvedIndex: Int?
        var id: PersistentIdentifier {
            entry.persistentModelID
        }
    }

    private func rows(entries: [PlaylistEntry], tracksByPath: [String: Track]) -> [Row] {
        var resolvedIndex = 0
        return entries.map { entry in
            guard let track = tracksByPath[entry.trackPath] else {
                return Row(entry: entry, track: nil, resolvedIndex: nil)
            }
            defer { resolvedIndex += 1 }
            return Row(entry: entry, track: track, resolvedIndex: resolvedIndex)
        }
    }

    public var body: some View {
        let entries = entries
        let tracksByPath = tracksByPath
        let rows = rows(entries: entries, tracksByPath: tracksByPath)
        let resolvedTracks = rows.compactMap(\.track)

        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note.list",
                    description: Text("Add songs from Songs or an Album using \"Add to Playlist…\".")
                )
            } else {
                List {
                    Section {
                        header(resolvedTracks: resolvedTracks)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                    Section {
                        ForEach(rows) { row in
                            if let track = row.track, let resolvedIndex = row.resolvedIndex {
                                ResolvableRow(
                                    index: resolvedIndex,
                                    track: track,
                                    isCurrent: coordinator.player.current?.relativePath == track.relativePath
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    coordinator.player.play(
                                        coordinator.playableTracks(from: resolvedTracks), startingAt: resolvedIndex
                                    )
                                }
                            } else {
                                DanglingRow(path: row.entry.trackPath)
                            }
                        }
                        .onMove { source, destination in
                            PlaylistOps.moveEntries(from: source, to: destination, in: playlist, in: modelContext)
                        }
                        .onDelete { offsets in
                            PlaylistOps.removeEntries(at: offsets, from: playlist, in: modelContext)
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

    private func header(resolvedTracks: [Track]) -> some View {
        VStack(spacing: 12) {
            Text(metadataLine(resolvedTracks: resolvedTracks))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    play(tracks: resolvedTracks)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(resolvedTracks.isEmpty)

                Button {
                    shuffle(tracks: resolvedTracks)
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(resolvedTracks.isEmpty)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 24)
    }

    private func metadataLine(resolvedTracks: [Track]) -> String {
        var parts: [String] = []
        parts.append(resolvedTracks.count == 1 ? "1 song" : "\(resolvedTracks.count) songs")
        let totalDuration = resolvedTracks.reduce(0) { $0 + $1.duration }
        parts.append(DurationText.format(totalDuration))
        return parts.joined(separator: " · ")
    }

    private func play(tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        coordinator.player.play(coordinator.playableTracks(from: tracks), startingAt: 0)
    }

    /// Plays the whole playlist, then ensures shuffle is on (never toggles
    /// it off if it's already shuffled).
    private func shuffle(tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        coordinator.player.play(coordinator.playableTracks(from: tracks), startingAt: 0)
        if !coordinator.player.isShuffled {
            coordinator.player.toggleShuffle()
        }
    }
}

private struct ResolvableRow: View {
    let index: Int
    let track: Track
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.tint)
                } else {
                    Text("\(index + 1)")
                        .font(OldPodTypography.timeReadout())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .lineLimit(1)
                Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            DurationText(track.duration)
        }
    }
}

/// A row for an entry whose `trackPath` no longer matches any `Track` (the
/// file was removed from the library). Not tappable — there's nothing to
/// play — but still reorderable/removable like any other row.
private struct DanglingRow: View {
    let path: String

    private var filenameStem: String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(filenameStem)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("file missing")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
