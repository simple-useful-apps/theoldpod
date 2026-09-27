import SwiftUI

/// Native, one-shot symbol replacement; playback never waits for animation.
public struct PlayPauseSymbol: View {
    private let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isPlaying: Bool) {
        self.isPlaying = isPlaying
    }

    public var body: some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
    }
}
