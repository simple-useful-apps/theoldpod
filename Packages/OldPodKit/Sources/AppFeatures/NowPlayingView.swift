import DesignSystem
import PlaybackEngine
import SwiftUI

/// The full "what's playing" surface: artwork, title/artist/album, the shared
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
                ArtworkImage(
                    artworkID: current.artworkID,
                    directory: artworkDirectory,
                    cornerRadius: 16,
                    pointSize: 320,
                    placeholderSystemName: current.bookID != nil ? "book.closed" : "music.note"
                )
                .frame(maxWidth: 320)
                .padding(.top, 24)

                VStack(spacing: 4) {
                    Text(current.title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .accessibilityIdentifier("nowPlayingTitle")
                    Text(current.subtitle)
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

                if current.bookID != nil {
                    ListeningControls(player: player)
                        .padding(.horizontal, 24)
                }

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

    private var transportRow: some View {
        HStack(spacing: 28) {
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
            }
            .foregroundStyle(player.isShuffled ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .accessibilityIdentifier("nowPlayingShuffleButton")
            .accessibilityLabel("Shuffle")
            .accessibilityValue(player.isShuffled ? "On" : "Off")

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
            }
            .accessibilityIdentifier("nowPlayingPreviousButton")
            .accessibilityLabel("Previous Track")

            Button {
                player.togglePlayPause()
            } label: {
                PlayPauseSymbol(isPlaying: player.isPlaying)
                    .font(.system(size: 44))
                    .frame(width: 52)
            }
            .accessibilityIdentifier("nowPlayingPlayPauseButton")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
            }
            .accessibilityIdentifier("nowPlayingNextButton")
            .accessibilityLabel("Next Track")

            Button {
                player.cycleRepeatMode()
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
            }
            .foregroundStyle(player.repeatMode != .off ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .accessibilityIdentifier("nowPlayingRepeatButton")
            .accessibilityLabel("Repeat")
            .accessibilityValue(player.repeatMode.rawValue)
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
        .disabled(player.current == nil)
    }
}
