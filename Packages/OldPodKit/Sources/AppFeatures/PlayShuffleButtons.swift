import SwiftUI

/// The Play (`.borderedProminent`) + Shuffle (`.bordered`) button pair shared
/// by every "playable collection" header (album, playlist, on both
/// platforms). Disabled together whenever the underlying playable track list
/// is empty — there is nothing sensible to play or shuffle.
public struct PlayShuffleButtons: View {
    let isEnabled: Bool
    let fullWidth: Bool
    let playAccessibilityIdentifier: String
    let shuffleAccessibilityIdentifier: String
    let onPlay: () -> Void
    let onShuffle: () -> Void

    /// - `fullWidth`: iOS's hero headers (Album, Playlist) want the two
    ///   buttons to split the row 50/50; Mac's compact header wants them
    ///   sized to their label, not stretched.
    /// - `playAccessibilityIdentifier`/`shuffleAccessibilityIdentifier`
    ///   default to generic identifiers; callers with an existing UI-test
    ///   contract (e.g. `AlbumDetailView`'s
    ///   "albumPlayButton"/"albumShuffleButton") can override them to keep
    ///   that contract intact.
    public init(
        isEnabled: Bool,
        fullWidth: Bool = true,
        playAccessibilityIdentifier: String = "playButton",
        shuffleAccessibilityIdentifier: String = "shuffleButton",
        onPlay: @escaping () -> Void,
        onShuffle: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.fullWidth = fullWidth
        self.playAccessibilityIdentifier = playAccessibilityIdentifier
        self.shuffleAccessibilityIdentifier = shuffleAccessibilityIdentifier
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
            .accessibilityIdentifier(playAccessibilityIdentifier)
            .disabled(!isEnabled)

            Button(action: onShuffle) {
                Label("Shuffle", systemImage: "shuffle")
                    .frame(maxWidth: fullWidth ? .infinity : nil)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(shuffleAccessibilityIdentifier)
            .disabled(!isEnabled)
        }
    }
}
