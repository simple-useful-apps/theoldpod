import Foundation

/// A single MP3 file discovered in the library folder.
public struct LibraryFile: Sendable, Equatable {
    public let relativePath: String
    public let url: URL
    public let size: Int64
    public let modified: Date
    /// `false` when this is an iCloud placeholder that hasn't been downloaded
    /// to the device yet. Always `true` for local files.
    public let isDownloaded: Bool

    public init(relativePath: String, url: URL, size: Int64, modified: Date, isDownloaded: Bool = true) {
        self.relativePath = relativePath
        self.url = url
        self.size = size
        self.modified = modified
        self.isDownloaded = isDownloaded
    }
}

/// A change to the library folder's contents, as reported by a
/// `LibraryFolderWatching` implementation.
public enum LibraryChange: Sendable, Equatable {
    case upsert(LibraryFile)
    case remove(relativePath: String)
}
