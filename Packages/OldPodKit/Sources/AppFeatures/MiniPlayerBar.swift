import DesignSystem
import PlaybackEngine
import SwiftUI

/// The persistent "what's playing" surface — always visible per the design
/// language, on every screen. M2 is transport-only (artwork, title/artist,
/// previous/play-pause/next); the full Now Playing screen and scrubber arrive
/// in M3.
public struct MiniPlayerBar: View {
    private let player: PlayerController

    public init(player: PlayerController) {
        self.player = player
    }

    public var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 0.5)

            HStack(spacing: 12) {
                ArtworkPlaceholder()
                    .frame(width: 40, height: 40)

                if let current = player.current {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.title)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(current.artist.isEmpty ? "Unknown Artist" : current.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Not Playing")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                #if os(macOS)
                    if player.current != nil {
                        DurationText(player.currentTime)
                    }
                #endif

                transportControls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private var transportControls: some View {
        HStack(spacing: 20) {
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
            }

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            }

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
            }
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
        .disabled(player.current == nil)
    }
}
