import Foundation
import os

/// Reads and writes `.m3u8` playlist files in a single directory (the
/// library's `Playlists` subfolder). Every write is atomic (temp file +
/// rename) so a concurrent reader — this app's own folder watcher, or the
/// user's file browser — never observes a half-written file.
public struct PlaylistFileStore: Sendable {
    /// `<libraryRoot>/Playlists`.
    public let directory: URL

    private static let logger = Logger(subsystem: "OldPodKit.CloudFiles", category: "PlaylistFileStore")

    public init(directory: URL) {
        self.directory = directory
    }

    public func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Serializes `entries` and atomically writes `<sanitized name>.m3u8`,
    /// creating the directory first if needed. Failures are logged, not
    /// thrown — a playlist edit that can't be persisted to disk shouldn't
    /// crash the app; the in-memory SwiftData state is still correct until
    /// the next reconcile.
    @discardableResult
    public func write(name: String, entries: [PlaylistFileEntry]) -> Bool {
        do {
            try ensureDirectoryExists()
            let text = PlaylistFileFormat.serialize(entries)
            let url = fileURL(for: name)
            try Data(text.utf8).write(to: url, options: .atomic)
            return true
        } catch {
            Self.logger.warning("PlaylistFileStore: failed to write playlist \(name, privacy: .public): \(error, privacy: .public)")
            return false
        }
    }

    /// Removes `<sanitized name>.m3u8` if present; a no-op otherwise.
    public func delete(name: String) {
        try? FileManager.default.removeItem(at: fileURL(for: name))
    }

    /// Every `.m3u8` file in the directory, keyed by its filename stem
    /// (verbatim — not re-sanitized, since it's already a valid filename)
    /// and parsed into entries. Matches the extension case-insensitively and
    /// skips hidden files. A failed read throws: callers must not interpret
    /// unavailable files as deleted playlists.
    public func readAll() throws -> [String: [PlaylistFileEntry]] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )

        var result: [String: [PlaylistFileEntry]] = [:]
        for url in urls {
            guard url.pathExtension.lowercased() == PlaylistFileFormat.fileExtension else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            result[url.deletingPathExtension().lastPathComponent] = PlaylistFileFormat.parse(text)
        }
        return result
    }

    private func fileURL(for name: String) -> URL {
        directory.appendingPathComponent(PlaylistFileFormat.sanitizedFilename(for: name))
            .appendingPathExtension(PlaylistFileFormat.fileExtension)
    }
}
