import DesignSystem
import PlaybackEngine
import SwiftUI

/// The full "what's playing" surface: artwork with an understated circular
/// progress ring (a click-wheel nod), title/artist/album, the shared
/// scrubber, and the full transport (shuffle, previous, play/pause, next,
/// repeat). Works standalone — iOS presents it as a sheet, macOS reuses it in
/// a mini-player window.
public struct NowPlayingView: View {
    private let player: PlayerController
    private let artworkDirectory: URL?

    public init(player: PlayerController, artworkDirectory: URL?) {
        self.player = player
        self.artworkDirectory = artworkDirectory
    }

    public var body: some View {
        if let current = player.current {
            VStack(spacing: 24) {
                artwork(for: current)
                    .frame(maxWidth: 320)
                    .padding(.top, 24)

                VStack(spacing: 4) {
                    Text(current.title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .accessibilityIdentifier("nowPlayingTitle")
                    Text(
                        "\(current.artist.isEmpty ? "Unknown Artist" : current.artist) · " +
                            (current.album.isEmpty ? "Unknown Album" : current.album)
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .accessibilityIdentifier("nowPlayingSubtitle")
                }
                .padding(.horizontal, 24)

                ScrubberView(player: player)
                    .padding(.horizontal, 24)

                transportRow
                    .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }
        } else {
            VStack(spacing: 12) {
                ArtworkPlaceholder(cornerRadius: 16)
                    .frame(maxWidth: 320)
                Text("Not Playing")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    /// Artwork with a thin, non-interactive circular progress ring drawn
    /// around it — trimmed to `currentTime / duration` and rotated so
    /// progress starts at 12 o'clock. Hidden entirely for zero-duration
    /// (untagged/failed) tracks, since there's nothing meaningful to show.
    private func artwork(for current: PlayableTrack) -> some View {
        ZStack {
            if current.duration > 0 {
                let progress = min(max(player.currentTime / current.duration, 0), 1)
                Circle()
                    .stroke(.quaternary, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            ArtworkImage(artworkID: current.artworkID, directory: artworkDirectory, cornerRadius: 16, pointSize: 320)
                .padding(12)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var transportRow: some View {
        HStack(spacing: 28) {
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
            }
            .foregroundStyle(player.isShuffled ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .accessibilityIdentifier("nowPlayingShuffleButton")

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
            }
            .accessibilityIdentifier("nowPlayingPreviousButton")

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
            }
            .accessibilityIdentifier("nowPlayingPlayPauseButton")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
            }
            .accessibilityIdentifier("nowPlayingNextButton")

            Button {
                player.cycleRepeatMode()
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
            }
            .foregroundStyle(player.repeatMode != .off ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .accessibilityIdentifier("nowPlayingRepeatButton")
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
        .disabled(player.current == nil)
    }
}
