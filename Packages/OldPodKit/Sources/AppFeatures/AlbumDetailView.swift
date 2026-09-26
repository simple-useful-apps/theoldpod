import DesignSystem
import Domain
import PlaybackEngine
import SwiftData
import SwiftUI

/// A single album's detail screen: hero artwork, title/artist/metadata line,
/// Play/Shuffle actions, and the track list (disc/track-ordered, matching
/// `LibraryGroups.albums(from:)`'s sort).
struct AlbumDetailView: View {
    let album: AlbumGroup
    let coordinator: LibraryCoordinator

    @Environment(\.modelContext) private var modelContext

    @State private var trackPendingPlaylistAdd: Track?
    @State private var deletionRequest: LibraryDeletionRequest?

    init(album: AlbumGroup, coordinator: LibraryCoordinator) {
        self.album = album
        self.coordinator = coordinator
    }

    private var tracks: [Track] {
        LibraryGroups.tracks(for: album.trackIDs, in: modelContext)
    }

    var body: some View {
        let tracks = tracks
        List {
            Section {
                header(tracks: tracks)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)

            Section {
                ForEach(Array(tracks.enumerated()), id: \.element.persistentModelID) { index, track in
                    TrackRow(
                        index: index,
                        track: track,
                        isCurrent: coordinator.player.current?.relativePath == track.relativePath
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        coordinator.play(tracks, startingAt: index)
                    }
                    .contextMenu {
                        TrackContextMenuContent(
                            track: track,
                            coordinator: coordinator,
                            onDelete: { deletionRequest = .songs([SongDeletionTarget(track: track)]) },
                            onAddToPlaylist: { trackPendingPlaylistAdd = track }
                        )
                    }
                    #if os(iOS)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            deletionRequest = .songs([SongDeletionTarget(track: track)])
                        } label: {
                            Label("Delete Song", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                    #endif
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(album.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .addToPlaylistSheet(for: $trackPendingPlaylistAdd)
            .libraryDeletionConfirmation(request: $deletionRequest, coordinator: coordinator)
    }

    private func header(tracks: [Track]) -> some View {
        VStack(spacing: 12) {
            ArtworkImage(artworkID: album.artworkID, directory: coordinator.artworkDirectory, cornerRadius: 8, pointSize: 200)
                .frame(width: 200, height: 200)

            VStack(spacing: 4) {
                Text(album.title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(album.artistName)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(metadataLine(tracks: tracks))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Distinct from the always-present (if disabled) mini-player
            // transport button, which shares the "Play" label whenever
            // nothing is queued yet.
            PlayShuffleButtons(
                isEnabled: !tracks.isEmpty,
                playAccessibilityIdentifier: "albumPlayButton",
                shuffleAccessibilityIdentifier: "albumShuffleButton",
                onPlay: { play(tracks: tracks) },
                onShuffle: { shuffle(tracks: tracks) }
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
    }

    private func metadataLine(tracks: [Track]) -> String {
        var parts: [String] = []
        if let year = album.year {
            parts.append(String(year))
        }
        let totalDuration = tracks.reduce(0) { $0 + $1.duration }
        parts.append(LibraryText.summary(songs: tracks.count, duration: totalDuration))
        return parts.joined(separator: " · ")
    }

    private func play(tracks: [Track]) {
        coordinator.play(tracks, startingAt: 0)
    }

    /// Plays the whole album shuffled, starting from a random track.
    private func shuffle(tracks: [Track]) {
        coordinator.playShuffled(tracks)
    }
}

private struct TrackRow: View {
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
                    Text(track.trackNumber.map(String.init) ?? "\(index + 1)")
                        .font(OldPodTypography.timeReadout())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, alignment: .center)

            Text(track.title)
                .font(.body)
                .lineLimit(1)

            Spacer()

            DurationText(track.duration)
        }
    }
}
