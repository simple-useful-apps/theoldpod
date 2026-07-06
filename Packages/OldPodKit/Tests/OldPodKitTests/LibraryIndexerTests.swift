import CloudFiles
import Domain
import Foundation
import LibraryStore
import MetadataImport
import SwiftData
import Testing

struct LibraryIndexerTests {
    @Test func appliesUpsertsThenARemove() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let artwork = ArtworkStore(directory: tempDirectory.appendingPathComponent("Artwork"))
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(LibrarySchema.models), configurations: [configuration])
        let indexer = LibraryIndexer(modelContainer: container, artwork: artwork)

        let taggedURL = TestFixtures.url("cbr-tagged.mp3")
        let untaggedURL = TestFixtures.url("untagged.mp3")

        let taggedFile = try LibraryFile(
            relativePath: "cbr-tagged.mp3",
            url: taggedURL,
            size: fileSize(taggedURL),
            modified: fileModified(taggedURL)
        )
        let untaggedFile = try LibraryFile(
            relativePath: "untagged.mp3",
            url: untaggedURL,
            size: fileSize(untaggedURL),
            modified: fileModified(untaggedURL)
        )

        await indexer.apply([.upsert(taggedFile), .upsert(untaggedFile)])

        let context = ModelContext(container)
        var tracks = try context.fetch(FetchDescriptor<Track>())
        #expect(tracks.count == 2)
        #expect(tracks.contains { $0.title == "Fixture One" })
        #expect(tracks.contains { $0.title == "untagged" })

        await indexer.apply([.remove(relativePath: "untagged.mp3")])

        tracks = try context.fetch(FetchDescriptor<Track>())
        #expect(tracks.count == 1)
        #expect(tracks.first?.title == "Fixture One")
    }
}

private func fileSize(_ url: URL) throws -> Int64 {
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    return Int64(values.fileSize ?? 0)
}

private func fileModified(_ url: URL) throws -> Date {
    let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
    return values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
}
