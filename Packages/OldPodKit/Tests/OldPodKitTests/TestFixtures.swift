import Foundation

/// Locates the repo's `Fixtures/` directory of generated test MP3s from this
/// test file's own path, so tests work regardless of the working directory
/// `swift test` is invoked from.
enum TestFixtures {
    static var directory: URL {
        // This file lives at <repo>/Packages/OldPodKit/Tests/OldPodKitTests/TestFixtures.swift.
        // Walk up to <repo>, then down into Fixtures/.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 5 {
            url.deleteLastPathComponent()
        }
        return url.appendingPathComponent("Fixtures", isDirectory: true)
    }

    static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }
}
