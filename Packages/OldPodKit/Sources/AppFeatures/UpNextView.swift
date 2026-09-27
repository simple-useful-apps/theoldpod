import DesignSystem
import PlaybackEngine
import SwiftUI

/// The play queue from the current track onward: the current track is
/// marked, and tapping any later track jumps straight to it.
public struct UpNextView: View {
    private let player: PlayerController
    @Environment(\.dismiss) private var dismiss

    public init(player: PlayerController) {
        self.player = player
    }

    private var currentIndex: Int? {
        player.queue.currentIndex
    }

    private var laterIndices: Range<Int> {
        guard let currentIndex else { return 0 ..< 0 }
        return (currentIndex + 1) ..< player.queue.items.count
    }

    public var body: some View {
        List {
            if let currentIndex {
                Section("Now Playing") {
                    row(player.queue.items[currentIndex], isCurrent: true)
                }
                Section("Up Next") {
                    if laterIndices.isEmpty {
                        Text("Nothing else is queued.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        // Indices are the identity: a queue may hold the same
                        // file twice.
                        ForEach(laterIndices, id: \.self) { index in
                            Button {
                                player.jump(toQueueIndex: index)
                            } label: {
                                row(player.queue.items[index], isCurrent: false)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("upNextRow")
                        }
                    }
                }
            }
        }
        .overlay {
            if currentIndex == nil {
                ContentUnavailableView(
                    "Nothing Playing",
                    systemImage: "list.bullet",
                    description: Text("Play a song to see what comes next.")
                )
            }
        }
        .navigationTitle("Up Next")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
    }

    private func row(_ track: PlayableTrack, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                Text(track.bookID != nil ? track.album : track.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Now Playing")
            } else if track.duration > 0 {
                DurationText(track.duration)
            }
        }
        .contentShape(Rectangle())
    }
}
