import AppFeatures
import DesignSystem
import PlaybackEngine
import SwiftUI

/// The Mac window's persistent "what's playing" surface — an iTunes-style
/// transport bar pinned to the top of the whole window (sidebar and detail
/// both), visible no matter which sidebar destination is selected. Left:
/// transport. Center: artwork "LCD" with title/artist·album and a compact
/// scrubber. Right: shuffle/repeat toggles.
struct PlayerBarView: View {
    let player: PlayerController
    let artworkDirectory: URL?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                transportCluster
                Spacer(minLength: 12)
                lcd
                Spacer(minLength: 12)
                if player.current?.bookID != nil {
                    ListeningControls(player: player)
                } else {
                    rightCluster
                }
            }
            // Hard minimum: the LCD (title + artist + inline scrubber) needs
            // ~54pt of content height; ideal-size negotiation under the
            // unified toolbar shortchanges it and the title clips. An explicit
            // minHeight is honored where fixedSize's ideal is not.
            .frame(minHeight: 56)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Rectangle()
                .fill(.quaternary)
                .frame(height: 0.5)
        }
        .background(.bar)
    }

    private var transportCluster: some View {
        HStack(spacing: 16) {
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
            }
            .accessibilityLabel("Previous Track")

            Button {
                player.togglePlayPause()
            } label: {
                PlayPauseSymbol(isPlaying: player.isPlaying)
                    .font(.system(size: 28))
                    .frame(width: 28)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
            }
            .accessibilityLabel("Next Track")
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
        .disabled(player.current == nil)
    }

    @ViewBuilder
    private var lcd: some View {
        if let current = player.current {
            HStack(spacing: 10) {
                ArtworkImage(
                    artworkID: current.artworkID,
                    directory: artworkDirectory,
                    pointSize: 40,
                    placeholderSystemName: current.bookID != nil ? "book.closed" : "music.note"
                )
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    // Identified for UI tests: the same title text is also
                    // visible in the Songs table row behind the bar once
                    // something is playing, so a bare label lookup is
                    // ambiguous — this identifier disambiguates it, the same
                    // way iOS's mini player uses "miniPlayerTitle".
                    Text(current.title)
                        .font(.callout)
                        .lineLimit(1)
                        .accessibilityIdentifier("playerBarTitle")
                    Text(current.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    ScrubberView(player: player, style: .inline)
                        .controlSize(.small)
                }
            }
            .frame(minWidth: 260, maxWidth: 440)
        } else {
            Text("Not Playing")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 260, maxWidth: 440)
        }
    }

    private var rightCluster: some View {
        HStack(spacing: 14) {
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
            }
            .accessibilityLabel("Shuffle")
            .accessibilityValue(player.isShuffled ? "On" : "Off")
            .foregroundStyle(player.isShuffled ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))

            Button {
                player.cycleRepeatMode()
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
            }
            .accessibilityLabel("Repeat")
            .accessibilityValue(player.repeatMode.rawValue)
            .foregroundStyle(player.repeatMode != .off ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.borderless)
        .imageScale(.medium)
    }
}
