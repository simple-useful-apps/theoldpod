import SwiftUI

public enum OldPodTypography {
    /// Monospaced-digit style for time readouts — a nod to the classic iTunes status line.
    public static func timeReadout(size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium).monospacedDigit()
    }
}
