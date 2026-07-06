import DesignSystem
import PlaybackEngine
import SwiftUI

/// A shared playback scrubber: a slider tracking `player.currentTime` with
/// elapsed/remaining time readouts. Used by NowPlayingView (both platforms)
/// and the Mac window's top player bar.
public struct ScrubberView: View {
    private let player: PlayerController

    @State private var isDragging = false
    @State private var dragValue: TimeInterval = 0

    public init(player: PlayerController) {
        self.player = player
    }

    private var duration: TimeInterval {
        player.current?.duration ?? 0
    }

    /// While dragging, the slider (and labels) show the in-progress drag
    /// position rather than fighting the periodic time observer; once the
    /// drag ends, `player.seek(to:)` catches the playhead up.
    private var displayedTime: TimeInterval {
        isDragging ? dragValue : min(player.currentTime, duration)
    }

    public var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(get: { displayedTime }, set: { dragValue = $0 }),
                in: 0 ... max(duration, 1),
                onEditingChanged: { editing in
                    isDragging = editing
                    if editing {
                        dragValue = player.currentTime
                    } else {
                        player.seek(to: dragValue)
                    }
                }
            )
            .disabled(player.current == nil || duration <= 0)

            HStack {
                Text(DurationText.format(displayedTime))
                Spacer()
                Text("-\(DurationText.format(max(duration - displayedTime, 0)))")
            }
            .font(OldPodTypography.timeReadout())
            .foregroundStyle(.secondary)
        }
    }
}
