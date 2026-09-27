import SwiftUI

/// The Play and Shuffle pair at the head of every playable collection
/// (album, playlist) on both platforms. Disabled together when there is
/// nothing to play.
public struct PlayShuffleButtons: View {
    let isEnabled: Bool
    /// iOS hero headers split the row between the two buttons; the Mac's
    /// compact header sizes them to their labels.
    let fullWidth: Bool
    let onPlay: () -> Void
    let onShuffle: () -> Void

    public init(
        isEnabled: Bool,
        fullWidth: Bool = true,
        onPlay: @escaping () -> Void,
        onShuffle: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.fullWidth = fullWidth
        self.onPlay = onPlay
        self.onShuffle = onShuffle
    }

    public var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: fullWidth ? .infinity : nil)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("playButton")
            .disabled(!isEnabled)

            Button(action: onShuffle) {
                Label("Shuffle", systemImage: "shuffle")
                    .frame(maxWidth: fullWidth ? .infinity : nil)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("shuffleButton")
            .disabled(!isEnabled)
        }
    }
}
