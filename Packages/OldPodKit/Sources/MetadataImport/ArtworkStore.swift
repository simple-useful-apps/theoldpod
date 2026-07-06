import CryptoKit
import Foundation

/// A content-addressed on-disk cache of embedded artwork images, keyed by the
/// first 16 hex characters of the image data's SHA-256 digest.
public struct ArtworkStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Writes `data` to `<id>.img` if not already present, returning its id.
    public func store(_ data: Data) throws -> String {
        let digest = SHA256.hash(data: data)
        let id = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        let idString = String(id)
        let fileURL = url(for: idString)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try data.write(to: fileURL, options: .atomic)
        }
        return idString
    }

    public func url(for id: String) -> URL {
        Self.fileURL(for: id, in: directory)
    }

    /// The canonical `<directory>/<id>.img` filename convention, exposed
    /// statically so callers that only have a directory (no `ArtworkStore`
    /// instance) — e.g. `NowPlayingBridge` — don't need to hand-roll it.
    public static func fileURL(for id: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id).img")
    }
}
