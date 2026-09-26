import PlaybackEngine
import SwiftUI

/// The shuffle toggle, lit with the accent color while on.
public struct ShuffleToggle: View {
    private let player: PlayerController

    public init(player: PlayerController) {
        self.player = player
    }

    public var body: some View {
        Button {
            player.toggleShuffle()
        } label: {
            Image(systemName: "shuffle")
        }
        .foregroundStyle(player.isShuffled ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .accessibilityIdentifier("shuffleToggle")
        .accessibilityLabel("Shuffle")
        .accessibilityValue(player.isShuffled ? "On" : "Off")
    }
}

/// The repeat-mode cycler (off, all, one), lit while repeating.
public struct RepeatToggle: View {
    private let player: PlayerController

    public init(player: PlayerController) {
        self.player = player
    }

    public var body: some View {
        Button {
            player.cycleRepeatMode()
        } label: {
            Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
        }
        .foregroundStyle(player.repeatMode != .off ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .accessibilityIdentifier("repeatToggle")
        .accessibilityLabel("Repeat")
        .accessibilityValue(player.repeatMode.rawValue)
    }
}
