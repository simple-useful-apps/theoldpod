import DesignSystem
import PlaybackEngine
import SwiftUI

/// The iPhone's persistent "what's playing" surface — mounted as the tab
/// view's bottom accessory on every screen: artwork, title/artist, and
/// previous/play-pause/next transport. Tapping it opens NowPlayingView as a
/// sheet (wired in RootTabView).
public struct MiniPlayerBar: View {
    private let player: PlayerController
    private let artworkDirectory: URL?

    public init(player: PlayerController, artworkDirectory: URL? = nil) {
        self.player = player
        self.artworkDirectory = artworkDirectory
    }

    public var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 0.5)

            HStack(spacing: 12) {
                ArtworkImage(
                    artworkID: player.current?.artworkID,
                    directory: artworkDirectory,
                    pointSize: 40,
                    placeholderSystemName: player.current?.bookID != nil ? "book.closed" : "music.note"
                )
                .frame(width: 40, height: 40)

                if let current = player.current {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.title)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityIdentifier("miniPlayerTitle")
                        Text(current.bookID != nil ? current.album : (current.artist.isEmpty ? "Unknown Artist" : current.artist))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityIdentifier("miniPlayerSubtitle")
                    }
                } else {
                    Text("Not Playing")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

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
                if player.current?.bookID != nil { player.skip(by: -15) } else { player.previous() }
            } label: {
                Image(systemName: player.current?.bookID != nil ? "gobackward.15" : "backward.fill")
            }
            .accessibilityIdentifier("miniPlayerPreviousButton")
            .accessibilityLabel(player.current?.bookID != nil ? "Back 15 seconds" : "Previous Track")

            Button {
                player.togglePlayPause()
            } label: {
                PlayPauseSymbol(isPlaying: player.isPlaying)
                    .frame(width: 24)
            }
            .accessibilityIdentifier("miniPlayerPlayPauseButton")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button {
                if player.current?.bookID != nil { player.skip(by: 15) } else { player.next() }
            } label: {
                Image(systemName: player.current?.bookID != nil ? "goforward.15" : "forward.fill")
            }
            .accessibilityIdentifier("miniPlayerNextButton")
            .accessibilityLabel(player.current?.bookID != nil ? "Forward 15 seconds" : "Next Track")
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
        .disabled(player.current == nil)
    }
}
