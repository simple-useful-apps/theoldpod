import Domain
import Foundation
import SwiftData

/// Builds the `ModelContainer` backing the library index.
public enum LibraryContainerFactory {
    /// `nil` url → default: `<Application Support>/theoldpod/Library.store`
    /// (parent directories created if missing).
    public static func make(storeURL: URL?) throws -> ModelContainer {
        let url = try storeURL ?? defaultStoreURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let configuration = ModelConfiguration(url: url)
        let schema = Schema(LibrarySchema.models)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func defaultStoreURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return appSupport
            .appendingPathComponent("theoldpod", isDirectory: true)
            .appendingPathComponent("Library.store")
    }
}
