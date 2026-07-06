import MetadataImport
import Testing

struct MetadataReaderTests {
    @Test func readsCBRTaggedFixture() async throws {
        let metadata = try await MetadataReader.read(from: TestFixtures.url("cbr-tagged.mp3"))
        #expect(metadata.title == "Fixture One")
        #expect(metadata.artist == "The Fixtures")
        #expect(metadata.album == "Test Tones")
        #expect(metadata.trackNumber == 1)
        #expect(metadata.year == 2001)
        #expect(metadata.genre == "Electronic")
        #expect(abs(metadata.duration - 3) < 0.5)
    }

    @Test func readsVBRTaggedFixtureFully() async throws {
        let metadata = try await MetadataReader.read(from: TestFixtures.url("vbr-tagged.mp3"))
        #expect(metadata.title == "Fixture Two")
        #expect(metadata.artist == "The Fixtures")
        #expect(metadata.album == "Test Tones")
        #expect(metadata.trackNumber == 2)
        #expect(metadata.year == 2001)
        #expect(abs(metadata.duration - 3) < 0.5)
    }

    @Test func readsArtworkFromTaggedFixture() async throws {
        let metadata = try await MetadataReader.read(from: TestFixtures.url("art-tagged.mp3"))
        #expect(metadata.artwork != nil)
    }

    @Test func untaggedFixtureHasNoTitle() async throws {
        let metadata = try await MetadataReader.read(from: TestFixtures.url("untagged.mp3"))
        #expect(metadata.title == nil)
    }
}
