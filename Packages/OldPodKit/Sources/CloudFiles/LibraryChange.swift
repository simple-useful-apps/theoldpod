import Foundation

/// A single MP3 file discovered in the library folder.
public struct LibraryFile: Sendable, Equatable {
    public let relativePath: String
    public let url: URL
    public let size: Int64
    public let modified: Date

    public init(relativePath: String, url: URL, size: Int64, modified: Date) {
        self.relativePath = relativePath
        self.url = url
        self.size = size
        self.modified = modified
    }
}

/// A change to the library folder's contents, as reported by a
/// `LibraryFolderWatching` implementation.
public enum LibraryChange: Sendable, Equatable {
    case upsert(LibraryFile)
    case remove(relativePath: String)
}
