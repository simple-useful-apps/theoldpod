import Darwin
import Foundation

/// The library folder, pinned to the directory that existed when the app
/// started. Every destructive file operation resolves its target through
/// here so a malformed relative path or a swapped-in symlink can never reach
/// a file outside the folder.
public struct LibraryRoot: Sendable {
    public enum Error: LocalizedError, Equatable {
        case unavailable
        case unsafePath
        case symbolicLink

        public var errorDescription: String? {
            switch self {
            case .unavailable:
                "The library folder changed or is no longer available. Refresh the library and try again."
            case .unsafePath:
                "The item is outside the library or has an unsafe path."
            case .symbolicLink:
                "Symbolic links can’t be changed from the app."
            }
        }
    }

    public let url: URL
    private let identity: Identity?

    public init(url: URL) {
        self.url = url.standardizedFileURL
        identity = try? Identity(of: self.url)
    }

    /// Throws unless the folder is still the same directory it was at init.
    public func validate() throws {
        guard let identity, try Identity(of: url) == identity else { throw Error.unavailable }
    }

    /// `relativePath` split into components, rejecting anything that could
    /// leave the folder: absolute paths, empty components, "." and "..".
    public static func components(of relativePath: String) throws -> [String] {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { throw Error.unsafePath }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw Error.unsafePath }
        return components
    }

    /// The file URL for `relativePath`, confirmed to sit strictly inside the
    /// folder. Touches the disk only to validate the root.
    public func resolve(_ relativePath: String) throws -> URL {
        try validate()
        let target = try Self.components(of: relativePath).reduce(url) { $0.appendingPathComponent($1) }.standardizedFileURL
        guard target.path.hasPrefix(url.path + "/") else { throw Error.unsafePath }
        return target
    }

    /// Walks `relativePath` on disk one component at a time. Throws on any
    /// symbolic link or on a non-directory parent; returns the leaf's file
    /// type, or `nil` when the leaf (or a parent) does not exist.
    public func inspect(_ relativePath: String) throws -> URLResourceValues? {
        let target = try resolve(relativePath)
        var candidate = url
        for component in try Self.components(of: relativePath) {
            candidate.appendPathComponent(component)
            let values: URLResourceValues
            do {
                values = try candidate.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            } catch {
                if Self.isNoSuchFile(error) { return nil }
                throw error
            }
            guard values.isSymbolicLink != true else { throw Error.symbolicLink }
            if candidate.standardizedFileURL != target {
                guard values.isDirectory == true else { throw Error.unsafePath }
            } else {
                return values
            }
        }
        return nil
    }

    private struct Identity: Equatable {
        let device: UInt64
        let inode: UInt64

        init(of url: URL) throws {
            var information = stat()
            guard lstat(url.resolvingSymlinksInPath().path, &information) == 0,
                  information.st_mode & S_IFMT == S_IFDIR
            else { throw Error.unavailable }
            device = UInt64(information.st_dev)
            inode = UInt64(information.st_ino)
        }
    }

    private static func isNoSuchFile(_ error: Swift.Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileNoSuchFile.rawValue)
            || (error.domain == NSPOSIXErrorDomain && error.code == ENOENT)
    }
}
