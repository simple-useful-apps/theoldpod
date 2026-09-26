import PlaybackEngine
import SwiftUI

/// Shared audiobook controls: chapter navigation stays in the main transport.
public struct ListeningControls: View {
    private let player: PlayerController
    public init(player: PlayerController) {
        self.player = player
    }

    public var body: some View {
        HStack(spacing: 20) {
            Button { player.skip(by: -15) } label: {
                Image(systemName: "gobackward.15").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(!player.canSeek)
            .accessibilityLabel("Back 15 seconds")
            .help("Back 15 seconds")
            Menu {
                ForEach(PlayerController.supportedSpeeds, id: \.self) { speed in
                    Button {
                        player.setSpeed(speed)
                    } label: {
                        if player.playbackSpeed == speed {
                            Label(Self.label(speed), systemImage: "checkmark")
                        } else {
                            Text(Self.label(speed))
                        }
                    }
                }
            } label: {
                Text(Self.label(player.playbackSpeed)).monospacedDigit().frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Playback speed")
            .accessibilityValue(Self.label(player.playbackSpeed))
            Button { player.skip(by: 15) } label: {
                Image(systemName: "goforward.15").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(!player.canSeek)
            .accessibilityLabel("Forward 15 seconds")
            .help("Forward 15 seconds")
        }
        .buttonStyle(.borderless)
        .disabled(player.current == nil)
    }

    private static func label(_ speed: Float) -> String {
        String(format: "%g×", speed)
    }
}
