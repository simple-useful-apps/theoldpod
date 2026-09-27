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

    /// Elapsed never exceeds the duration, so the formatted duration is the
    /// widest readout this track can produce (digits are monospaced).
    private var widestReadout: String {
        DurationText.format(duration)
    }

    private var elapsedText: some View {
        FixedWidthReadout(
            text: DurationText.format(displayedTime),
            template: widestReadout,
            alignment: style == .inline ? .trailing : .leading
        )
    }

    private var remainingText: some View {
        FixedWidthReadout(
            text: "-\(DurationText.format(max(duration - displayedTime, 0)))",
            template: "-\(widestReadout)",
            alignment: style == .inline ? .leading : .trailing
        )
    }
}

/// A time readout that keeps the width of `template`, so the slider beside
/// it doesn't shift as the time gains a digit (9:59 → 10:00).
private struct FixedWidthReadout: View {
    let text: String
    let template: String
    let alignment: Alignment

    var body: some View {
        Text(template)
            .fixedSize()
            .hidden()
            .accessibilityHidden(true)
            .overlay(alignment: alignment) {
                Text(text)
                    .fixedSize()
            }
    }
}
