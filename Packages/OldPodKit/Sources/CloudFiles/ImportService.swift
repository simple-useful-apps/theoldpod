import CryptoKit
import Foundation

/// The outcome of an `ImportService.importFiles(at:)` call.
public struct ImportResult: Sendable, Equatable {
    /// Relative paths created (or already present) under the library root.
    public let imported: [String]
    /// Source filenames rejected (not `.mp3`) or that failed to copy.
    public let skipped: [String]
}

/// Copies user-picked files into the library folder. Purely a file-system
/// operation: it never touches SwiftData. The folder watcher discovers the
/// copied files and the indexer turns them into `Track`s.
public struct ImportService: Sendable {
    private let libraryRoot: URL
    /// `FileManager` isn't `Sendable`, but `.default` is documented as safe to
    /// use from any thread.
    private nonisolated(unsafe) let fileManager = FileManager.default

    public init(libraryRoot: URL) {
        self.libraryRoot = libraryRoot
    }

    /// Copies the given files into the library root, flat (no subfolders
    /// invented). Only `.mp3` (case-insensitive) files are accepted.
    public func importFiles(at urls: [URL]) async -> ImportResult {
        if !fileManager.fileExists(atPath: libraryRoot.path) {
            try? fileManager.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        }

        var imported: [String] = []
        var skipped: [String] = []

        for url in urls {
            let filename = url.lastPathComponent
            guard url.pathExtension.lowercased() == "mp3" else {
                skipped.append(filename)
                continue
            }

            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if let relativePath = copyIntoLibrary(from: url, filename: filename) {
                imported.append(relativePath)
            } else {
                skipped.append(filename)
            }
        }

        return ImportResult(imported: imported, skipped: skipped)
    }

    /// Copies `source` into the library root under `filename`, resolving name
    /// collisions. Returns the relative path written (or the path of an
    /// identical file already there), or `nil` on failure.
    private func copyIntoLibrary(from source: URL, filename: String) -> String? {
        guard let sourceSize = fileSize(at: source) else { return nil }

        var candidate = filename
        var attempt = 1
        while true {
            let destination = libraryRoot.appendingPathComponent(candidate)
            if let existingSize = fileSize(at: destination) {
                // Same size alone isn't proof of identical content, so also
                // compare a content hash before treating this as a no-op:
                // a same-name, same-size, *different*-content file should
                // still get copied in under a suffixed name, not silently
                // dropped.
                if existingSize == sourceSize, filesAreIdentical(source, destination) {
                    // Identical file already present: treat as already imported.
                    return candidate
                }
                attempt += 1
                candidate = numberedFilename(filename, attempt: attempt)
                continue
            }

            do {
                try fileManager.copyItem(at: source, to: destination)
                return candidate
            } catch {
                return nil
            }
        }
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize
        else { return nil }
        return Int64(size)
    }

    /// SHA-256 comparison of `lhs` and `rhs`'s full contents. `false` if
    /// either can't be read (in which case the caller falls back to treating
    /// them as distinct, i.e. the suffixed-name copy path).
    private func filesAreIdentical(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let lhsDigest = sha256(at: lhs), let rhsDigest = sha256(at: rhs) else { return false }
        return lhsDigest == rhsDigest
    }

    private func sha256(at url: URL) -> SHA256.Digest? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data)
    }

    private func numberedFilename(_ filename: String, attempt: Int) -> String {
        let name = filename as NSString
        let stem = name.deletingPathExtension
        let ext = name.pathExtension
        return "\(stem) \(attempt).\(ext)"
    }
}
