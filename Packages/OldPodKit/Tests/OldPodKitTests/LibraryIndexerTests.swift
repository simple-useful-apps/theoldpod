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

    @Test func upsertIsANoOpWhenSizeAndModifiedAreUnchanged() async throws {
        let (indexer, context, _, tempDirectory) = try makeIndexer()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let url = TestFixtures.url("cbr-tagged.mp3")
        let file = try LibraryFile(
            relativePath: "cbr-tagged.mp3", url: url, size: fileSize(url), modified: fileModified(url)
        )

        await indexer.apply([.upsert(file)])
        var tracks = try context.fetch(FetchDescriptor<Track>())
        let track = try #require(tracks.first)
        #expect(track.title == "Fixture One")

        // Mutate the stored title directly, then re-apply the identical file
        // stat. If the indexer re-read metadata it would revert this back to
        // "Fixture One"; since size+modified are unchanged it should skip
        // the read entirely and leave the mutation intact.
        track.title = "Mutated Title"
        try context.save()

        await indexer.apply([.upsert(file)])

        tracks = try context.fetch(FetchDescriptor<Track>())
        #expect(tracks.first?.title == "Mutated Title")
    }

    @Test func upsertRereadsMetadataWhenModifiedDateChanges() async throws {
        let (indexer, context, _, tempDirectory) = try makeIndexer()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let url = TestFixtures.url("cbr-tagged.mp3")
        let originalModified = try fileModified(url)
        let file = try LibraryFile(
            relativePath: "cbr-tagged.mp3", url: url, size: fileSize(url), modified: originalModified
        )

        await indexer.apply([.upsert(file)])
        var tracks = try context.fetch(FetchDescriptor<Track>())
        let track = try #require(tracks.first)
        #expect(track.title == "Fixture One")

        track.title = "Mutated Title"
        try context.save()

        let changedFile = try LibraryFile(
            relativePath: "cbr-tagged.mp3",
            url: url,
            size: fileSize(url),
            modified: originalModified.addingTimeInterval(1)
        )
        await indexer.apply([.upsert(changedFile)])

        tracks = try context.fetch(FetchDescriptor<Track>())
        #expect(tracks.first?.title == "Fixture One")
    }

    @Test func addedAtIsSetOnInsertAndPreservedAcrossAnUpdate() async throws {
        let (indexer, context, _, tempDirectory) = try makeIndexer()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let url = TestFixtures.url("cbr-tagged.mp3")
        let originalModified = try fileModified(url)
        let file = try LibraryFile(
            relativePath: "cbr-tagged.mp3", url: url, size: fileSize(url), modified: originalModified
        )

        let beforeInsert = Date()
        await indexer.apply([.upsert(file)])
        let afterInsert = Date()

        var tracks = try context.fetch(FetchDescriptor<Track>())
        let insertedAddedAt = try #require(tracks.first).addedAt
        #expect(insertedAddedAt >= beforeInsert.addingTimeInterval(-1))
        #expect(insertedAddedAt <= afterInsert.addingTimeInterval(1))

        let changedFile = try LibraryFile(
            relativePath: "cbr-tagged.mp3",
            url: url,
            size: fileSize(url),
            modified: originalModified.addingTimeInterval(1)
        )
        await indexer.apply([.upsert(changedFile)])

        tracks = try context.fetch(FetchDescriptor<Track>())
        #expect(tracks.first?.addedAt == insertedAddedAt)
    }

    @Test func artworkIsStoredForTaggedFixtureAndNilForUntaggedFixture() async throws {
        let (indexer, context, artwork, tempDirectory) = try makeIndexer()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let artURL = TestFixtures.url("art-tagged.mp3")
        let cbrURL = TestFixtures.url("cbr-tagged.mp3")
        let artFile = try LibraryFile(
            relativePath: "art-tagged.mp3", url: artURL, size: fileSize(artURL), modified: fileModified(artURL)
        )
        let cbrFile = try LibraryFile(
            relativePath: "cbr-tagged.mp3", url: cbrURL, size: fileSize(cbrURL), modified: fileModified(cbrURL)
        )

        await indexer.apply([.upsert(artFile), .upsert(cbrFile)])

        let tracks = try context.fetch(FetchDescriptor<Track>())
        let artTrack = try #require(tracks.first { $0.relativePath == "art-tagged.mp3" })
        let cbrTrack = try #require(tracks.first { $0.relativePath == "cbr-tagged.mp3" })

        #expect(cbrTrack.artworkID == nil)
        let artworkID = try #require(artTrack.artworkID)
        #expect(FileManager.default.fileExists(atPath: artwork.url(for: artworkID).path))
    }

    @Test func unreadableFileStillIndexesAndDoesNotAbortTheRestOfTheBatch() async throws {
        let (indexer, context, _, tempDirectory) = try makeIndexer()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let missingURL = tempDirectory.appendingPathComponent("does-not-exist.mp3")
        let missingFile = LibraryFile(
            relativePath: "does-not-exist.mp3", url: missingURL, size: 0, modified: Date()
        )

        let validURL = TestFixtures.url("cbr-tagged.mp3")
        let validFile = try LibraryFile(
            relativePath: "cbr-tagged.mp3", url: validURL, size: fileSize(validURL), modified: fileModified(validURL)
        )

        // The unreadable file is deliberately applied first, so a batch-abort
        // bug would show up as the valid file after it never getting indexed.
        await indexer.apply([.upsert(missingFile), .upsert(validFile)])

        let tracks = try context.fetch(FetchDescriptor<Track>())
        #expect(tracks.count == 2)

        let missingTrack = try #require(tracks.first { $0.relativePath == "does-not-exist.mp3" })
        #expect(missingTrack.title == "does-not-exist")
        #expect(missingTrack.duration == 0)

        let validTrack = try #require(tracks.first { $0.relativePath == "cbr-tagged.mp3" })
        #expect(validTrack.title == "Fixture One")
    }

    @Test func removingANonexistentPathIsHarmless() async throws {
        let (indexer, context, _, tempDirectory) = try makeIndexer()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        await indexer.apply([.remove(relativePath: "never-existed.mp3")])

        let tracks = try context.fetch(FetchDescriptor<Track>())
        #expect(tracks.isEmpty)
    }

    @Test func notDownloadedFileSkipsMetadataReadEvenForATaggedFixture() async throws {
        let (indexer, context, _, tempDirectory) = try makeIndexer()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        // cbr-tagged.mp3 has real ID3 tags ("Fixture One"); the indexer must
        // not read them (that would force-download an iCloud placeholder) as
        // long as isDownloaded is false.
        let url = TestFixtures.url("cbr-tagged.mp3")
        let file = try LibraryFile(
            relativePath: "cbr-tagged.mp3", url: url, size: fileSize(url), modified: fileModified(url),
            isDownloaded: false
        )

        await indexer.apply([.upsert(file)])

        let tracks = try context.fetch(FetchDescriptor<Track>())
        let track = try #require(tracks.first)
        #expect(track.title == "cbr-tagged")
        #expect(track.duration == 0)
        #expect(track.isDownloaded == false)
    }

    @Test func downloadedFlipFromFalseToTrueWithSameSizeAndDateTriggersAReread() async throws {
        let (indexer, context, _, tempDirectory) = try makeIndexer()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let url = TestFixtures.url("cbr-tagged.mp3")
        let size = try fileSize(url)
        let modified = try fileModified(url)

        let notDownloaded = LibraryFile(
            relativePath: "cbr-tagged.mp3", url: url, size: size, modified: modified, isDownloaded: false
        )
        await indexer.apply([.upsert(notDownloaded)])

        var tracks = try context.fetch(FetchDescriptor<Track>())
        var track = try #require(tracks.first)
        #expect(track.title == "cbr-tagged")
        #expect(track.isDownloaded == false)

        // Same size and modified date — only isDownloaded differs — must
        // still trigger a re-read, since the file now has real bytes.
        let nowDownloaded = LibraryFile(
            relativePath: "cbr-tagged.mp3", url: url, size: size, modified: modified, isDownloaded: true
        )
        await indexer.apply([.upsert(nowDownloaded)])

        tracks = try context.fetch(FetchDescriptor<Track>())
        track = try #require(tracks.first)
        #expect(track.title == "Fixture One")
        #expect(track.isDownloaded == true)
    }
}

private func makeIndexer() throws -> (
    indexer: LibraryIndexer, context: ModelContext, artwork: ArtworkStore, tempDirectory: URL
) {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let artwork = ArtworkStore(directory: tempDirectory.appendingPathComponent("Artwork"))
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: Schema(LibrarySchema.models), configurations: [configuration])
    let indexer = LibraryIndexer(modelContainer: container, artwork: artwork)
    let context = ModelContext(container)
    return (indexer, context, artwork, tempDirectory)
}

private func fileSize(_ url: URL) throws -> Int64 {
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    return Int64(values.fileSize ?? 0)
}

private func fileModified(_ url: URL) throws -> Date {
    let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
    return values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
}
