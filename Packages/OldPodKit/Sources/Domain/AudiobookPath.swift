import Foundation

/// Book identity lives in the visible folder structure, not in the index.
/// Files under Audiobooks/<book name>/ remain grouped after rebuilding it.
public enum AudiobookPath {
    public static func bookID(for relativePath: String) -> String? {
        let parts = relativePath.split(separator: "/")
        guard parts.count >= 3, parts[0] == "Audiobooks" else { return nil }
        return String(parts[1])
    }
}

public extension Track {
    var bookID: String? {
        AudiobookPath.bookID(for: relativePath)
    }

    var isAudiobook: Bool {
        bookID != nil
    }
}
