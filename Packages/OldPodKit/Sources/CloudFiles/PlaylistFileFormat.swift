import Foundation

/// One line-pair of a `.m3u8` playlist file: the track it points at, plus
/// advisory display data that's re-derived from the library on export and
/// ignored on import (see `PlaylistFileSync`).
public struct PlaylistFileEntry: Sendable, Equatable {
    /// Library-root-relative path, e.g. "Album/song.mp3".
    public var trackPath: String
    /// Advisory display title — not authoritative, never trusted on import.
    public var title: String
    /// Advisory duration in seconds; `-1` means unknown (a dangling entry
    /// whose track couldn't be resolved at export time).
    public var seconds: Int

    public init(trackPath: String, title: String, seconds: Int) {
        self.trackPath = trackPath
        self.title = title
        self.seconds = seconds
    }
}

/// Reads and writes the extended-M3U playlist format theoldpod uses for its
/// on-disk playlist files. Pure text transformation — no file I/O here, see
/// `PlaylistFileStore` for that.
public enum PlaylistFileFormat {
    public static let fileExtension = "m3u8"

    /// `#EXTM3U` header, then one `#EXTINF:<seconds>,<title>` / `<trackPath>`
    /// line pair per entry. Newlines inside a title (titles come from ID3
    /// tags, which can contain anything) are collapsed to spaces so they
    /// never split into a stray extra line.
    public static func serialize(_ entries: [PlaylistFileEntry]) -> String {
        var lines = ["#EXTM3U"]
        for entry in entries {
            let flatTitle = entry.title.replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            lines.append("#EXTINF:\(entry.seconds),\(flatTitle)")
            lines.append(entry.trackPath)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Tolerant parser: blank lines, `#EXTM3U`, and unrecognized `#` comments
    /// are ignored; a malformed `#EXTINF` line (non-integer seconds prefix)
    /// is dropped rather than throwing, leaving the next path line to fall
    /// back on its defaults. Every non-`#` line is a track path that
    /// consumes whatever `#EXTINF` immediately preceded it (or the defaults,
    /// if none did).
    public static func parse(_ text: String) -> [PlaylistFileEntry] {
        var entries: [PlaylistFileEntry] = []
        var pendingSeconds: Int?
        var pendingTitle: String?

        // Swift treats "\r\n" as a single `Character` (one grapheme
        // cluster), so splitting on the `Character` "\n" alone would never
        // find a match inside a CRLF pair — normalize CRLF (and stray CR) to
        // LF first so the split actually breaks CRLF-terminated files apart.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("#EXTINF:") {
                let payload = trimmed.dropFirst("#EXTINF:".count)
                // Title is everything after the FIRST comma — titles may
                // themselves contain commas.
                guard let commaIndex = payload.firstIndex(of: ",") else {
                    pendingSeconds = nil
                    pendingTitle = nil
                    continue
                }
                let secondsText = payload[payload.startIndex ..< commaIndex]
                guard let seconds = Int(secondsText) else {
                    pendingSeconds = nil
                    pendingTitle = nil
                    continue
                }
                pendingSeconds = seconds
                pendingTitle = String(payload[payload.index(after: commaIndex)...])
                continue
            }

            if trimmed.hasPrefix("#") { continue } // #EXTM3U or an unrecognized comment

            let trackPath = trimmed
            let title = pendingTitle ?? stem(of: trackPath)
            let seconds = pendingSeconds ?? -1
            entries.append(PlaylistFileEntry(trackPath: trackPath, title: title, seconds: seconds))
            pendingSeconds = nil
            pendingTitle = nil
        }
        return entries
    }

    /// The full sanitization contract for a playlist file's stem: trim
    /// surrounding whitespace/newlines, then remove every "/" and ":"
    /// character (both are path separators on one Apple platform or
    /// another). Remove newlines and leading dots so names cannot create
    /// hidden files. An empty result becomes "New Playlist". PlaylistStore
    /// adds a numbered suffix when this name is already occupied.
    public static func sanitizedFilename(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.filter { $0 != "/" && $0 != ":" && !$0.isNewline }
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return stripped.isEmpty ? "New Playlist" : stripped
    }

    private static func stem(of trackPath: String) -> String {
        let lastComponent = (trackPath as NSString).lastPathComponent
        return (lastComponent as NSString).deletingPathExtension
    }
}
