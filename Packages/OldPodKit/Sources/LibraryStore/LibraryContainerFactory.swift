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
        // cloudKitDatabase MUST be explicit: the default (.automatic) sees the
        // iCloud container in the entitlements and silently enables CloudKit
        // mirroring — which this architecture rejects (files sync via iCloud
        // Drive; the store is a rebuildable local index) and which refuses to
        // load our non-optional schema at all. Surfaced the moment real
        // entitlements were signed in.
        let schema = Schema(LibrarySchema.models)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
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
