import DesignSystem
import Foundation

/// Shared user-facing strings for library counts and summaries, so wording
/// and pluralization can't drift between views/platforms.
public enum LibraryText {
    /// "1 song" / "N songs".
    public static func songCount(_ count: Int) -> String {
        count == 1 ? "1 song" : "\(count) songs"
    }

    /// "1 album" / "N albums".
    public static func albumCount(_ count: Int) -> String {
        count == 1 ? "1 album" : "\(count) albums"
    }

    /// "1 item was moved to Trash." / "N items were moved to Trash."
    public static func itemCount(_ count: Int, verb: String) -> String {
        count == 1 ? "1 item was \(verb)." : "\(count) items were \(verb)."
    }

    /// "N songs · m:ss" (or "h:mm:ss" past an hour, via `DurationText.format`).
    public static func summary(songs: Int, duration: TimeInterval) -> String {
        "\(songCount(songs)) · \(DurationText.format(duration))"
    }
}
