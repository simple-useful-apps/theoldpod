import Foundation

/// The outcome of `LibraryLocation.resolve()`: where the library root ended
/// up living, and whether that's the iCloud-backed location or the local
/// fallback.
public struct ResolvedLibrary: Sendable {
    public let root: URL
    public let isCloud: Bool

    public init(root: URL, isCloud: Bool) {
        self.root = root
        self.isCloud = isCloud
    }
}

/// Resolves where the library folder lives on disk.
public enum LibraryLocation {
    /// Default local root: `<user Documents>/Music`, created if missing.
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

    /// Resolves the library root for this run. Checks the default ubiquity
    /// container off the main thread (`FileManager.url(forUbiquityContainerIdentifier:)`
    /// is a blocking call) and, if the app has iCloud entitlements and the
    /// user is signed in, uses `<container>/Documents/Music` (created if
    /// missing). Without an iCloud account — or, today, without the
    /// entitlements themselves — falls back to `defaultRoot()`.
    public static func resolve() async -> ResolvedLibrary {
        let cloudRoot = await Task.detached(priority: .utility) {
            resolveCloudRoot()
        }.value

        if let cloudRoot {
            return ResolvedLibrary(root: cloudRoot, isCloud: true)
        }
        return ResolvedLibrary(root: localFallbackRoot(), isCloud: false)
    }

    private static func resolveCloudRoot() -> URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let musicRoot = container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Music", isDirectory: true)
        if !FileManager.default.fileExists(atPath: musicRoot.path) {
            try? FileManager.default.createDirectory(at: musicRoot, withIntermediateDirectories: true)
        }
        return musicRoot
    }

    /// `defaultRoot()`, but non-throwing: falls further back to a raw,
    /// possibly-not-yet-created path if even the documents directory lookup
    /// fails, since `resolve()` must always return something usable.
    private static func localFallbackRoot() -> URL {
        if let root = try? defaultRoot() {
            return root
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("Music", isDirectory: true)
    }
}
