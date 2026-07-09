import CloudFiles
import Testing

struct PlaylistFileFormatTests {
    @Test func serializeProducesTheGoldenExtendedM3UText() {
        let entries = [
            PlaylistFileEntry(trackPath: "Album/song.mp3", title: "Song One", seconds: 180),
            PlaylistFileEntry(trackPath: "Loose Track.mp3", title: "Comma, In Title", seconds: 42),
        ]

        let text = PlaylistFileFormat.serialize(entries)

        #expect(text == """
        #EXTM3U
        #EXTINF:180,Song One
        Album/song.mp3
        #EXTINF:42,Comma, In Title
        Loose Track.mp3

        """)
    }

    @Test func parseSerializeRoundTrips() {
        let entries = [
            PlaylistFileEntry(trackPath: "Album/song.mp3", title: "Song One", seconds: 180),
            PlaylistFileEntry(trackPath: "Loose Track.mp3", title: "Comma, In Title", seconds: 42),
        ]

        let roundTripped = PlaylistFileFormat.parse(PlaylistFileFormat.serialize(entries))

        #expect(roundTripped == entries)
    }

    @Test func parseToleratesCRLFLineEndings() {
        let text = "#EXTM3U\r\n#EXTINF:100,Title\r\nsong.mp3\r\n"

        let entries = PlaylistFileFormat.parse(text)

        #expect(entries == [PlaylistFileEntry(trackPath: "song.mp3", title: "Title", seconds: 100)])
    }

    @Test func parseSkipsBlankLines() {
        let text = "#EXTM3U\n\n#EXTINF:100,Title\n\nsong.mp3\n\n"

        let entries = PlaylistFileFormat.parse(text)

        #expect(entries == [PlaylistFileEntry(trackPath: "song.mp3", title: "Title", seconds: 100)])
    }

    @Test func parseDefaultsTitleAndSecondsWhenExtinfIsMissing() {
        let text = "#EXTM3U\nAlbum/My Song.mp3\n"

        let entries = PlaylistFileFormat.parse(text)

        #expect(entries == [PlaylistFileEntry(trackPath: "Album/My Song.mp3", title: "My Song", seconds: -1)])
    }

    @Test func parseIgnoresMalformedExtinfAndFallsBackToDefaultsForTheNextPath() {
        let text = "#EXTM3U\n#EXTINF:not-a-number,Title\nsong.mp3\n"

        let entries = PlaylistFileFormat.parse(text)

        #expect(entries == [PlaylistFileEntry(trackPath: "song.mp3", title: "song", seconds: -1)])
    }

    @Test func parseIgnoresStrayCommentLines() {
        let text = "#EXTM3U\n# a random comment\n#EXTINF:10,Title\nsong.mp3\n"

        let entries = PlaylistFileFormat.parse(text)

        #expect(entries == [PlaylistFileEntry(trackPath: "song.mp3", title: "Title", seconds: 10)])
    }

    @Test func danglingEntrySerializesWithNegativeOneDuration() {
        let entries = [PlaylistFileEntry(trackPath: "nope/missing.mp3", title: "missing", seconds: -1)]

        let text = PlaylistFileFormat.serialize(entries)

        #expect(text.contains("#EXTINF:-1,missing\n"))
    }

    @Test func sanitizedFilenameRemovesSlashesAndColons() {
        #expect(PlaylistFileFormat.sanitizedFilename(for: "AC/DC: Live") == "ACDC Live")
    }

    @Test func sanitizedFilenameTrimsWhitespace() {
        #expect(PlaylistFileFormat.sanitizedFilename(for: "  Road Trip  ") == "Road Trip")
    }

    @Test func sanitizedFilenameFallsBackToPlaylistWhenEverythingIsStripped() {
        #expect(PlaylistFileFormat.sanitizedFilename(for: "///:::") == "Playlist")
        #expect(PlaylistFileFormat.sanitizedFilename(for: "   ") == "Playlist")
        #expect(PlaylistFileFormat.sanitizedFilename(for: "") == "Playlist")
    }
}
