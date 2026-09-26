import Foundation

/// The size, modification date and file-system identity of a file at one
/// moment. Two reads that compare equal saw the same bytes, so a slow
/// metadata read can be checked against the file it started from.
public struct FileVersion: Sendable, Equatable {
    public let size: Int64
    public let modified: Date
    public let resourceIdentifier: String?

    public init(size: Int64, modified: Date, resourceIdentifier: String?) {
        self.size = size
        self.modified = modified
        self.resourceIdentifier = resourceIdentifier
    }

    /// Throws `CocoaError.fileReadNoSuchFile` when the file cannot be stat'd.
    public init(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
        guard let size = values.fileSize, let modified = values.contentModificationDate else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        self.init(
            size: Int64(size),
            modified: modified,
            resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) }
        )
    }

    public static func current(at url: URL) -> FileVersion? {
        try? FileVersion(at: url)
    }
}
