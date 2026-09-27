import AppFeatures
import AppKit
import DesignSystem
import PlaybackEngine
import SwiftUI

/// The Mini Player window's content: a thin iTunes-style strip — small
/// artwork, title/artist, transport, and an inline scrubber — plus a Keep on
/// Top toggle, so what's playing can sit beside other work.
struct MiniPlayerView: View {
    static let size = CGSize(width: 380, height: 80)
    static let keepOnTopKey = "miniPlayerKeepsOnTop"

    let player: PlayerController
    let artworkDirectory: URL?

    @AppStorage(keepOnTopKey) private var keepsOnTop = false

    var body: some View {
        HStack(spacing: 10) {
            ArtworkImage(
                artworkID: player.current?.artworkID,
                directory: artworkDirectory,
                pointSize: 56,
                placeholderSystemName: player.current?.bookID != nil ? "book.closed" : "music.note"
            )
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.current?.title ?? "Not Playing")
                            .font(.callout)
                            .lineLimit(1)
                            .foregroundStyle(player.current == nil ? .secondary : .primary)
                        if let current = player.current {
                            Text(current.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    transport
                    keepOnTopToggle
                }
                if player.current != nil {
                    ScrubberView(player: player, style: .inline)
                        .controlSize(.mini)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(WindowLevelSetter(isFloating: keepsOnTop))
    }

    private var transport: some View {
        HStack(spacing: 10) {
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
                    .font(.system(size: 18))
                    .frame(width: 18)
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
        .disabled(player.current == nil)
    }

    private var keepOnTopToggle: some View {
        Toggle(isOn: $keepsOnTop) {
            Image(systemName: keepsOnTop ? "pin.fill" : "pin")
        }
        .toggleStyle(.button)
        .buttonStyle(.borderless)
        .accessibilityLabel("Keep on Top")
        .help(keepsOnTop ? "Stop keeping the Mini Player on top" : "Keep the Mini Player on top of other windows")
    }
}

/// Applies Keep on Top to the hosting window immediately. The scene's
/// `.windowLevel` covers new windows; this covers toggling an open one.
private struct WindowLevelSetter: NSViewRepresentable {
    let isFloating: Bool

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context _: Context) {
        let level: NSWindow.Level = isFloating ? .floating : .normal
        // The view may not be in a window on first update.
        Task { @MainActor in
            view.window?.level = level
        }
    }
}
