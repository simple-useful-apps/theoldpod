import SwiftUI

/// Renders a `TimeInterval` as a duration readout: `m:ss`, or `h:mm:ss` at one
/// hour or more. Never truncates.
public struct DurationText: View {
    private let interval: TimeInterval

    public init(_ interval: TimeInterval) {
        self.interval = interval
    }

    public var body: some View {
        Text(Self.format(interval))
            .font(OldPodTypography.timeReadout())
            .foregroundStyle(.secondary)
    }

    /// Formats as `m:ss`, or `h:mm:ss` once the duration reaches one hour.
    public nonisolated static func format(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0, interval < Double(Int.max) else { return "0:00" }
        let totalSeconds = Int(interval.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
