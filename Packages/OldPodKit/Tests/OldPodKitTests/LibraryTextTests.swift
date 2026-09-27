import AppFeatures
import Testing

struct LibraryTextTests {
    @Test func playlistCountOmitsMissingWhenNoneAreMissing() {
        #expect(LibraryText.playlistSongCount(songs: 3, missing: 0) == "3 songs")
        #expect(LibraryText.playlistSongCount(songs: 1, missing: 0) == "1 song")
    }

    @Test func playlistCountCallsOutMissingFiles() {
        #expect(LibraryText.playlistSongCount(songs: 2, missing: 1) == "2 songs, 1 missing")
        #expect(LibraryText.playlistSongCount(songs: 0, missing: 2) == "0 songs, 2 missing")
    }

    @Test func playlistSummaryAppendsDuration() {
        #expect(LibraryText.playlistSummary(songs: 2, missing: 1, duration: 35) == "2 songs, 1 missing · 0:35")
    }

    @Test func chapterCountPluralizes() {
        #expect(LibraryText.chapterCount(1) == "1 chapter")
        #expect(LibraryText.chapterCount(4) == "4 chapters")
    }
}
