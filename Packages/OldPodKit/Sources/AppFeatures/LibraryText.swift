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

    /// A playlist's count: "N songs", or "N songs, M missing" when some
    /// entries' files are gone. `songs` counts only playable entries.
    public static func playlistSongCount(songs: Int, missing: Int) -> String {
        missing > 0 ? "\(songCount(songs)), \(missing) missing" : songCount(songs)
    }

    /// "N songs, M missing · m:ss" — `playlistSongCount` plus the playable
    /// entries' total duration.
    public static func playlistSummary(songs: Int, missing: Int, duration: TimeInterval) -> String {
        "\(playlistSongCount(songs: songs, missing: missing)) · \(DurationText.format(duration))"
    }

    /// "1 chapter" / "N chapters".
    public static func chapterCount(_ count: Int) -> String {
        count == 1 ? "1 chapter" : "\(count) chapters"
    }
}
