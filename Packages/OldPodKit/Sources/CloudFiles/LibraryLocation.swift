import Foundation

/// Resolves where the library folder lives on disk.
public enum LibraryLocation {
    /// Default local root: `<user Documents>/Music`, created if missing.
    /// The iCloud-backed variant arrives in M5.
    public static func defaultRoot() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let musicRoot = documents.appendingPathComponent("Music", isDirectory: true)
        if !FileManager.default.fileExists(atPath: musicRoot.path) {
            try FileManager.default.createDirectory(at: musicRoot, withIntermediateDirectories: true)
        }
        return musicRoot
    }
}
