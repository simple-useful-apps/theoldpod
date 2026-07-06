import Foundation

/// A per-file stat snapshot, decoupled from `LibraryFile` (which also carries
/// a resolved `URL`) so that any `LibraryFolderWatching` implementation can
/// diff two `[relativePath: LibraryFileStat]` snapshots the same way.
public struct LibraryFileStat: Sendable, Equatable {
    public let size: Int64
    public let modified: Date
    public let isDownloaded: Bool

    public init(size: Int64, modified: Date, isDownloaded: Bool) {
        self.size = size
        self.modified = modified
        self.isDownloaded = isDownloaded
    }
}

/// Shared diffing core for `LibraryFolderWatching` implementations: turns two
/// full snapshots into the minimal set of `LibraryChange`s between them.
public enum LibrarySnapshotDiff {
    /// Upserts every path that's new in `new` or whose `size`/`modified`/
    /// `isDownloaded` differs from `old`; removes every path present in
    /// `old` but missing from `new`. `resolveURL` turns a relative path into
    /// the file's `URL` for the emitted `LibraryFile`.
    public static func changes(
        from old: [String: LibraryFileStat],
        to new: [String: LibraryFileStat],
        resolveURL: (String) -> URL
    ) -> [LibraryChange] {
        var changes: [LibraryChange] = []

        for (path, stat) in new {
            if let previous = old[path] {
                if previous != stat {
                    changes.append(.upsert(libraryFile(path: path, stat: stat, resolveURL: resolveURL)))
                }
            } else {
                changes.append(.upsert(libraryFile(path: path, stat: stat, resolveURL: resolveURL)))
            }
        }
        for path in old.keys where new[path] == nil {
            changes.append(.remove(relativePath: path))
        }

        return changes
    }

    private static func libraryFile(
        path: String, stat: LibraryFileStat, resolveURL: (String) -> URL
    ) -> LibraryFile {
        LibraryFile(
            relativePath: path,
            url: resolveURL(path),
            size: stat.size,
            modified: stat.modified,
            isDownloaded: stat.isDownloaded
        )
    }
}
