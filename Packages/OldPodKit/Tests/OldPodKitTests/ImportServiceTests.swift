import CloudFiles
import Foundation
import Testing

struct ImportServiceTests {
    @Test func importsAnMp3AndAppearsUnderRootWithItsRelativePath() async throws {
        let (sourceDirectory, root) = try makeTempDirectories()
        defer { cleanUp(sourceDirectory, root) }

        // Root doesn't exist yet: importFiles should create it.
        #expect(!FileManager.default.fileExists(atPath: root.path))

        let sourceURL = try writeFile(named: "Track.mp3", data: fixtureData(), in: sourceDirectory)

        // A plain local file URL isn't security-scoped: this also exercises
        // the tolerant (non-scoped) path through startAccessingSecurityScopedResource.
        let service = ImportService(libraryRoot: root)
        let result = await service.importFiles(at: [sourceURL])

        #expect(result.imported == ["Track.mp3"])
        #expect(result.skipped.isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Track.mp3").path))
    }

    @Test func rejectsNonMp3Extensions() async throws {
        let (sourceDirectory, root) = try makeTempDirectories()
        defer { cleanUp(sourceDirectory, root) }

        let textURL = try writeFile(named: "notes.txt", data: Data("hello".utf8), in: sourceDirectory)
        let m4aURL = try writeFile(named: "song.m4a", data: fixtureData(), in: sourceDirectory)

        let service = ImportService(libraryRoot: root)
        let result = await service.importFiles(at: [textURL, m4aURL])

        #expect(result.imported.isEmpty)
        #expect(Set(result.skipped) == ["notes.txt", "song.m4a"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func collisionWithDifferentSizeGetsANumberedName() async throws {
        let (sourceDirectory, root) = try makeTempDirectories()
        defer { cleanUp(sourceDirectory, root) }

        let smallData = fixtureData(named: "cbr-tagged.mp3")
        let largeData = fixtureData(named: "art-tagged.mp3")
        #expect(smallData.count != largeData.count)

        // Pre-populate the root with a differently-sized "Song.mp3".
        _ = try writeFile(named: "Song.mp3", data: smallData, in: root)

        let sourceURL = try writeFile(named: "Song.mp3", data: largeData, in: sourceDirectory)
        let service = ImportService(libraryRoot: root)
        let result = await service.importFiles(at: [sourceURL])

        #expect(result.imported == ["Song 2.mp3"])
        #expect(result.skipped.isEmpty)

        let originalData = try Data(contentsOf: root.appendingPathComponent("Song.mp3"))
        #expect(originalData == smallData) // untouched

        let numberedData = try Data(contentsOf: root.appendingPathComponent("Song 2.mp3"))
        #expect(numberedData == largeData)
    }

    @Test func repeatedCollisionsIncrementTheNumberedSuffix() async throws {
        let (sourceDirectory, root) = try makeTempDirectories()
        defer { cleanUp(sourceDirectory, root) }

        let dataOne = fixtureData(named: "cbr-tagged.mp3")
        let dataTwo = fixtureData(named: "art-tagged.mp3")
        let dataThree = fixtureData(named: "vbr-tagged.mp3")
        #expect(Set([dataOne.count, dataTwo.count, dataThree.count]).count == 3)

        _ = try writeFile(named: "Song.mp3", data: dataOne, in: root)
        _ = try writeFile(named: "Song 2.mp3", data: dataTwo, in: root)

        let sourceURL = try writeFile(named: "Song.mp3", data: dataThree, in: sourceDirectory)
        let service = ImportService(libraryRoot: root)
        let result = await service.importFiles(at: [sourceURL])

        #expect(result.imported == ["Song 3.mp3"])
        let thirdData = try Data(contentsOf: root.appendingPathComponent("Song 3.mp3"))
        #expect(thirdData == dataThree)
    }

    @Test func sameNameSameSizeDifferentContentGetsANumberedNameRatherThanBeingSkipped() async throws {
        let (sourceDirectory, root) = try makeTempDirectories()
        defer { cleanUp(sourceDirectory, root) }

        let original = fixtureData()
        var modified = original
        // Flip a byte partway through: same size as `original`, but
        // different content (and therefore a different SHA-256), so this
        // must NOT be treated as an already-imported duplicate.
        let flipIndex = modified.count / 2
        modified[flipIndex] = modified[flipIndex] &+ 1
        #expect(modified.count == original.count)
        #expect(modified != original)

        _ = try writeFile(named: "Song.mp3", data: original, in: root)

        let sourceURL = try writeFile(named: "Song.mp3", data: modified, in: sourceDirectory)
        let service = ImportService(libraryRoot: root)
        let result = await service.importFiles(at: [sourceURL])

        #expect(result.imported == ["Song 2.mp3"])
        #expect(result.skipped.isEmpty)

        let originalOnDisk = try Data(contentsOf: root.appendingPathComponent("Song.mp3"))
        #expect(originalOnDisk == original) // untouched

        let numberedData = try Data(contentsOf: root.appendingPathComponent("Song 2.mp3"))
        #expect(numberedData == modified)
    }

    @Test func identicalSizeReImportDoesNotDuplicateButIsStillReportedImported() async throws {
        let (sourceDirectory, root) = try makeTempDirectories()
        defer { cleanUp(sourceDirectory, root) }

        let data = fixtureData()
        _ = try writeFile(named: "Song.mp3", data: data, in: root)

        // Same size as the existing file (re-import scenario): the copy
        // should be skipped silently, but still reported as imported.
        let sourceURL = try writeFile(named: "Song.mp3", data: data, in: sourceDirectory)
        let service = ImportService(libraryRoot: root)
        let result = await service.importFiles(at: [sourceURL])

        #expect(result.imported == ["Song.mp3"])
        #expect(result.skipped.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["Song.mp3"])
    }

    @Test func importingIntoAMissingRootCreatesIt() async throws {
        let sourceDirectory = try makeTempDirectory()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { cleanUp(sourceDirectory, root) }

        #expect(!FileManager.default.fileExists(atPath: root.path))

        let sourceURL = try writeFile(named: "Track.mp3", data: fixtureData(), in: sourceDirectory)
        let service = ImportService(libraryRoot: root)
        let result = await service.importFiles(at: [sourceURL])

        #expect(result.imported == ["Track.mp3"])
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }
}

// MARK: - Helpers

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Returns a source directory (created) and a library root directory (NOT
/// created, so tests can exercise `ImportService` creating it on demand).
private func makeTempDirectories() throws -> (source: URL, root: URL) {
    let source = try makeTempDirectory()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    return (source, root)
}

private func cleanUp(_ urls: URL...) {
    for url in urls {
        try? FileManager.default.removeItem(at: url)
    }
}

@discardableResult
private func writeFile(named name: String, data: Data, in directory: URL) throws -> URL {
    if !FileManager.default.fileExists(atPath: directory.path) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let url = directory.appendingPathComponent(name)
    try data.write(to: url)
    return url
}

private func fixtureData(named name: String = "cbr-tagged.mp3") -> Data {
    (try? Data(contentsOf: TestFixtures.url(name))) ?? Data()
}
