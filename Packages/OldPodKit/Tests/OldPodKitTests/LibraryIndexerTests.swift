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

        // A private copy, so its on-disk modification date can really change:
        // the indexer re-checks the file's current version before committing
        // and ignores a change whose stat no longer matches the disk.
        let url = tempDirectory.appendingPathComponent("cbr-tagged.mp3")
        try FileManager.default.copyItem(at: TestFixtures.url("cbr-tagged.mp3"), to: url)
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

        let changedModified = originalModified.addingTimeInterval(1)
        try FileManager.default.setAttributes([.modificationDate: changedModified], ofItemAtPath: url.path)
        // A fresh URL, as the watcher would hand over: the original caches
        // its resource values and would still report the old date.
        let changedURL = URL(fileURLWithPath: url.path)
        let changedFile = try LibraryFile(
            relativePath: "cbr-tagged.mp3",
            url: changedURL,
            size: fileSize(changedURL),
            modified: fileModified(changedURL)
        )
        await indexer.apply([.upsert(changedFile)])

        tracks = try context.fetch(FetchDescriptor<Track>())
        #expect(tracks.first?.title == "Fixture One")
    }

    @Test func addedAtIsSetOnInsertAndPreservedAcrossAnUpdate() async throws {
        let (indexer, context, _, tempDirectory) = try makeIndexer()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        // A private copy, so its on-disk modification date can really change:
        // the indexer re-checks the file's current version before committing
        // and ignores a change whose stat no longer matches the disk.
        let url = tempDirectory.appendingPathComponent("cbr-tagged.mp3")
        try FileManager.default.copyItem(at: TestFixtures.url("cbr-tagged.mp3"), to: url)
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

        let changedModified = originalModified.addingTimeInterval(1)
        try FileManager.default.setAttributes([.modificationDate: changedModified], ofItemAtPath: url.path)
        // A fresh URL, as the watcher would hand over: the original caches
        // its resource values and would still report the old date.
        let changedURL = URL(fileURLWithPath: url.path)
        let changedFile = try LibraryFile(
            relativePath: "cbr-tagged.mp3",
            url: changedURL,
            size: fileSize(changedURL),
            modified: fileModified(changedURL)
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

        // Present on disk but not decodable audio. (A file that no longer
        // exists is deliberately skipped: its removal is on its way.)
        let missingURL = tempDirectory.appendingPathComponent("does-not-exist.mp3")
        try Data("not audio".utf8).write(to: missingURL)
        let missingFile = try LibraryFile(
            relativePath: "does-not-exist.mp3", url: missingURL, size: fileSize(missingURL), modified: fileModified(missingURL)
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

    @Test func initialSnapshotReconciliationPrunesTracksMissingFromTheSnapshot() async throws {
        let (indexer, context, _, tempDirectory) = try makeIndexer()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let cbr = TestFixtures.url("cbr-tagged.mp3")
        let vbr = TestFixtures.url("vbr-tagged.mp3")
        let cbrFile = try LibraryFile(
            relativePath: "cbr-tagged.mp3", url: cbr, size: fileSize(cbr), modified: fileModified(cbr)
        )
        let vbrFile = try LibraryFile(
            relativePath: "vbr-tagged.mp3", url: vbr, size: fileSize(vbr), modified: fileModified(vbr)
        )

        // Seed a two-track store (e.g. from a previous library root).
        await indexer.apply([.upsert(cbrFile), .upsert(vbrFile)])
        #expect(try context.fetch(FetchDescriptor<Track>()).count == 2)

        // A new session's INITIAL snapshot contains only one of them: the
        // other's row must be pruned — the folder is the source of truth.
        await indexer.apply([.upsert(cbrFile)], reconcilingFullSnapshot: true)
        let tracks = try context.fetch(FetchDescriptor<Track>())
        #expect(tracks.count == 1)
        #expect(tracks.first?.relativePath == "cbr-tagged.mp3")

        // A plain incremental batch must NOT prune (default behavior).
        await indexer.apply([.upsert(vbrFile)])
        await indexer.apply([.upsert(cbrFile)])
        #expect(try context.fetch(FetchDescriptor<Track>()).count == 2)
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
