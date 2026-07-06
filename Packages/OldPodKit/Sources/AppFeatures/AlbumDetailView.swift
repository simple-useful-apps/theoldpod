import DesignSystem
import Domain
import PlaybackEngine
import SwiftData
import SwiftUI

/// A single album's detail screen: hero artwork, title/artist/metadata line,
/// Play/Shuffle actions, and the track list (disc/track-ordered, matching
/// `LibraryGroups.albums(from:)`'s sort).
public struct AlbumDetailView: View {
    let album: AlbumGroup
    let coordinator: LibraryCoordinator

    @Environment(\.modelContext) private var modelContext

    @State private var trackPendingPlaylistAdd: Track?
    @State private var isPresentingAddToPlaylist = false

    public init(album: AlbumGroup, coordinator: LibraryCoordinator) {
        self.album = album
        self.coordinator = coordinator
    }

    private var tracks: [Track] {
        LibraryGroups.tracks(for: album.trackIDs, in: modelContext)
    }

    public var body: some View {
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
                        coordinator.player.play(coordinator.playableTracks(from: tracks), startingAt: index)
                    }
                    .contextMenu {
                        trackContextMenu(for: track)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(album.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .sheet(isPresented: $isPresentingAddToPlaylist) {
                if let trackPendingPlaylistAdd {
                    AddToPlaylistSheet(track: trackPendingPlaylistAdd)
                }
            }
    }

    @ViewBuilder
    private func trackContextMenu(for track: Track) -> some View {
        Button {
            if let playable = coordinator.playableTracks(from: [track]).first {
                coordinator.player.playNext(playable)
            }
        } label: {
            Label("Play Next", systemImage: "text.insert")
        }

        Button {
            if let playable = coordinator.playableTracks(from: [track]).first {
                coordinator.player.append(playable)
            }
        } label: {
            Label("Add to Queue", systemImage: "text.append")
        }

        Button {
            trackPendingPlaylistAdd = track
            isPresentingAddToPlaylist = true
        } label: {
            Label("Add to Playlist…", systemImage: "music.note.list")
        }
    }

    private func header(tracks: [Track]) -> some View {
        VStack(spacing: 12) {
            ArtworkImage(artworkID: album.artworkID, directory: coordinator.artworkDirectory, cornerRadius: 8)
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

            HStack(spacing: 12) {
                Button {
                    play(tracks: tracks)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    shuffle(tracks: tracks)
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
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
        parts.append(tracks.count == 1 ? "1 song" : "\(tracks.count) songs")
        let totalDuration = tracks.reduce(0) { $0 + $1.duration }
        parts.append(DurationText.format(totalDuration))
        return parts.joined(separator: " · ")
    }

    private func play(tracks: [Track]) {
        coordinator.player.play(coordinator.playableTracks(from: tracks), startingAt: 0)
    }

    /// Plays the whole album, then ensures shuffle is on (never toggles it
    /// off if it's already shuffled).
    private func shuffle(tracks: [Track]) {
        coordinator.player.play(coordinator.playableTracks(from: tracks), startingAt: 0)
        if !coordinator.player.isShuffled {
            coordinator.player.toggleShuffle()
        }
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
