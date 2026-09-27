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
                    .deleteSwipeAction("Delete Song") { deletionRequest = .songs([SongDeletionTarget(track: track)]) }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(album.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .addToPlaylistSheet(for: $trackPendingPlaylistAdd, coordinator: coordinator)
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

            PlayShuffleButtons(
                isEnabled: !tracks.isEmpty,
                onPlay: { coordinator.play(tracks) },
                onShuffle: { coordinator.playShuffled(tracks) }
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
