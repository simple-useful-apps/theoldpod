import Foundation
import MetadataImport
import Testing

struct ArtworkStoreTests {
    @Test func storingTheSameDataTwiceReturnsTheSameIDAndWritesOneFile() throws {
        let directory = makeArtworkDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ArtworkStore(directory: directory)

        let data = Data("artwork-bytes".utf8)
        let firstID = try store.store(data)
        let secondID = try store.store(data)

        #expect(firstID == secondID)
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(contents.count == 1)
    }

    @Test func storingDifferentDataReturnsDifferentIDs() throws {
        let directory = makeArtworkDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ArtworkStore(directory: directory)

        let firstID = try store.store(Data("one".utf8))
        let secondID = try store.store(Data("two".utf8))

        #expect(firstID != secondID)
    }

    @Test func urlForIDRoundTripsTheStoredData() throws {
        let directory = makeArtworkDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ArtworkStore(directory: directory)

        let original = Data("round-trip-bytes".utf8)
        let id = try store.store(original)
        let readBack = try Data(contentsOf: store.url(for: id))

        #expect(readBack == original)
    }
}

/// Returns a not-yet-created unique directory URL; `ArtworkStore.init`
/// creates it (with intermediate directories) on first use.
private func makeArtworkDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}
