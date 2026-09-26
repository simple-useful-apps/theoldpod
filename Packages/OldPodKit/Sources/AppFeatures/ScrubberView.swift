import DesignSystem
import PlaybackEngine
import SwiftUI

/// A shared playback scrubber: a slider tracking `player.currentTime` with
/// elapsed/remaining time readouts. Used by NowPlayingView (both platforms)
/// and the Mac window's top player bar.
public struct ScrubberView: View {
    /// `.stacked` puts the time readouts on their own row beneath the slider
    /// (Now Playing); `.inline` puts elapsed · slider · remaining on one row
    /// for height-constrained homes like the Mac player bar.
    public enum Style {
        case stacked
        case inline
    }

    private let player: PlayerController
    private let style: Style

    public init(player: PlayerController, style: Style = .stacked) {
        self.player = player
        self.style = style
    }

    private var duration: TimeInterval {
        player.currentDuration
    }

    /// Keep one source of truth for touch, keyboard and accessibility seeking.
    /// A separate editing flag can outlive a cancelled gesture or track change,
    /// leaving the time readouts frozen even while playback advances.
    private var displayedTime: TimeInterval {
        min(player.currentTime, duration)
    }

    public var body: some View {
        switch style {
        case .stacked:
            VStack(spacing: 4) {
                slider
                HStack {
                    elapsedText
                    Spacer()
                    remainingText
                }
                .font(OldPodTypography.timeReadout())
                .foregroundStyle(.secondary)
            }
        case .inline:
            HStack(spacing: 8) {
                elapsedText
                slider
                remainingText
            }
            .font(OldPodTypography.timeReadout())
            .foregroundStyle(.secondary)
        }
    }

    private var slider: some View {
        Slider(
            value: Binding(get: { displayedTime }, set: { player.seek(to: $0) }),
            in: 0 ... max(duration, 1)
        )
        .accessibilityLabel("Playback position")
        .accessibilityValue(DurationText.format(displayedTime))
        .disabled(!player.canSeek)
    }

    private var elapsedText: some View {
        Text(DurationText.format(displayedTime))
    }

    private var remainingText: some View {
        Text("-\(DurationText.format(max(duration - displayedTime, 0)))")
    }
}
