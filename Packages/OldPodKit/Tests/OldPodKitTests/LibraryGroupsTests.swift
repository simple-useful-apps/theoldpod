import AppFeatures
import Domain
import Foundation
import SwiftData
import Testing

@MainActor
struct LibraryGroupsTests {
    @Test func compilationAlbumsGroupByAlbumArtistNotArtist() {
        let context = makeContext()
        let a = insert(
            context, title: "Track A", artist: "Artist One", album: "Various Hits", albumArtist: "Various Artists"
        )
        let b = insert(
            context, title: "Track B", artist: "Artist Two", album: "Various Hits", albumArtist: "Various Artists"
        )

        let albums = LibraryGroups.albums(from: [a, b])

        #expect(albums.count == 1)
        #expect(albums[0].artistName == "Various Artists")
        #expect(Set(albums[0].trackIDs) == Set([a.persistentModelID, b.persistentModelID]))
    }

    @Test func albumGroupingIsCaseAndWhitespaceInsensitiveAndKeepsFirstSeenCasing() {
        let context = makeContext()
        let a = insert(context, title: "Come Together", artist: "The Beatles", album: "Abbey Road")
        let b = insert(context, title: "Something", artist: "The Beatles", album: "  abbey road ")

        let albums = LibraryGroups.albums(from: [a, b])

        #expect(albums.count == 1)
        #expect(albums[0].title == "Abbey Road")
        #expect(albums[0].trackIDs.count == 2)
    }

    @Test func emptyArtistAndAlbumDisplayAsUnknown() {
        let context = makeContext()
        let track = insert(context, title: "Mystery Track", artist: "", album: "")

        let albums = LibraryGroups.albums(from: [track])

        #expect(albums.count == 1)
        #expect(albums[0].title == "Unknown Album")
        #expect(albums[0].artistName == "Unknown Artist")

        let artists = LibraryGroups.artists(from: [track])
        #expect(artists.count == 1)
        #expect(artists[0].name == "Unknown Artist")
    }

    @Test func tracksWithinAnAlbumSortByDiscThenTrackNumber() {
        let context = makeContext()
        let discTwoTrackOne = insert(
            context, title: "Z Song", artist: "Band", album: "Double LP", trackNumber: 1, discNumber: 2
        )
        let discOneTrackTwo = insert(
            context, title: "B Song", artist: "Band", album: "Double LP", trackNumber: 2, discNumber: 1
        )
        let discOneTrackOne = insert(
            context, title: "A Song", artist: "Band", album: "Double LP", trackNumber: 1, discNumber: 1
        )

        // Deliberately passed out of expected order.
        let albums = LibraryGroups.albums(from: [discTwoTrackOne, discOneTrackTwo, discOneTrackOne])

        #expect(albums.count == 1)
        #expect(albums[0].trackIDs == [
            discOneTrackOne.persistentModelID,
            discOneTrackTwo.persistentModelID,
            discTwoTrackOne.persistentModelID,
        ])
    }

    @Test func artistsSortByArticleStrippedNameCaseInsensitively() {
        let context = makeContext()
        let aardvark = insert(context, title: "Song", artist: "Aardvark")
        let theFixtures = insert(context, title: "Song", artist: "The Fixtures")
        let fooFighters = insert(context, title: "Song", artist: "Foo Fighters")

        let artists = LibraryGroups.artists(from: [theFixtures, fooFighters, aardvark])

        // "The Fixtures" sorts under "Fixtures" (F), landing between
        // "Aardvark" and "Foo Fighters" ("Fixtures" < "Foo Fighters").
        #expect(artists.map(\.name) == ["Aardvark", "The Fixtures", "Foo Fighters"])
    }

    @Test func artistsSortIgnoringDiacritics() {
        let context = makeContext()
        let zebras = insert(context, title: "Song", artist: "Zebras")
        let emile = insert(context, title: "Song", artist: "Émile")
        let drone = insert(context, title: "Song", artist: "Drone Unit")

        let artists = LibraryGroups.artists(from: [zebras, emile, drone])

        #expect(artists.map(\.name) == ["Drone Unit", "Émile", "Zebras"])
    }

    @Test func compilationTrackArtistsGetTheirOwnGroupsAlongsideTheAlbumArtist() throws {
        let context = makeContext()
        let bjork = insert(
            context, title: "Joga", artist: "Björk", album: "Now That's Tones", albumArtist: "Various Artists"
        )
        let sigur = insert(
            context, title: "Hoppipolla", artist: "Sigur Rós", album: "Now That's Tones", albumArtist: "Various Artists"
        )

        let artists = LibraryGroups.artists(from: [bjork, sigur])

        #expect(artists.map(\.name) == ["Björk", "Sigur Rós", "Various Artists"])
        let various = try #require(artists.first { $0.name == "Various Artists" })
        #expect(various.trackCount == 2)
        #expect(various.albums.first?.trackIDs.count == 2)

        let bjorkGroup = try #require(artists.first { $0.name == "Björk" })
        #expect(bjorkGroup.trackCount == 1)
        #expect(bjorkGroup.albums.map(\.title) == ["Now That's Tones"])
        #expect(bjorkGroup.albums.first?.artistName == "Various Artists")
        #expect(bjorkGroup.albums.first?.trackIDs == [bjork.persistentModelID])
    }

    @Test func trackArtistMatchingAnAlbumArtistMergesCaseInsensitively() {
        let context = makeContext()
        // Seen first as a lowercase compilation credit; the group should
        // still display the album-artist casing and hold both tracks.
        let compTrack = insert(
            context, title: "Stripes", artist: "the zebras", album: "Now That's Tones",
            albumArtist: "Various Artists", year: 2010
        )
        let ownTrack = insert(context, title: "Graze", artist: "The Zebras", album: "Savanna", year: 2004)

        let artists = LibraryGroups.artists(from: [compTrack, ownTrack])
        let zebras = artists.filter { $0.id == "the zebras" }

        #expect(zebras.count == 1)
        #expect(zebras.first?.name == "The Zebras")
        #expect(zebras.first?.trackCount == 2)
        // Year order, regardless of the compilation's "Various Artists" credit.
        #expect(zebras.first?.albums.map(\.title) == ["Savanna", "Now That's Tones"])
    }

    @Test func trackArtistSameAsAlbumArtistIsNotDoubleCounted() {
        let context = makeContext()
        let track = insert(context, title: "Song", artist: "band", album: "Record", albumArtist: "Band")

        let artists = LibraryGroups.artists(from: [track])

        #expect(artists.count == 1)
        #expect(artists[0].name == "Band")
        #expect(artists[0].trackCount == 1)
    }

    @Test func emptyTrackArtistOnACompilationAddsNoUnknownArtist() {
        let context = makeContext()
        let track = insert(context, title: "Song", artist: "", album: "Mix", albumArtist: "Various Artists")

        let artists = LibraryGroups.artists(from: [track])

        #expect(artists.map(\.name) == ["Various Artists"])
    }

    @Test func unknownArtistSortsLast() {
        let context = makeContext()
        let unknown = insert(context, title: "Song", artist: "")
        let zebras = insert(context, title: "Song", artist: "Zebras")
        let abba = insert(context, title: "Song", artist: "ABBA")
        let upbeat = insert(context, title: "Song", artist: "Upbeat")

        let artists = LibraryGroups.artists(from: [unknown, zebras, abba, upbeat])

        #expect(artists.map(\.name) == ["ABBA", "Upbeat", "Zebras", "Unknown Artist"])
    }

    @Test func unknownAlbumsSortAfterTitledAlbums() {
        let context = makeContext()
        let untitledByAbba = insert(context, title: "Song", artist: "ABBA", album: "")
        let zebrasAlbum = insert(context, title: "Song", artist: "Zebras", album: "Stripes")
        let abbaAlbum = insert(context, title: "Song", artist: "ABBA", album: "Arrival")
        let unknownArtistAlbum = insert(context, title: "Song", artist: "", album: "Found Tape")
        let fullyUnknown = insert(context, title: "Song", artist: "", album: "")

        let albums = LibraryGroups.albums(from: [untitledByAbba, zebrasAlbum, abbaAlbum, unknownArtistAlbum, fullyUnknown])

        #expect(albums.map { "\($0.artistName)/\($0.title)" } == [
            "ABBA/Arrival",
            "Zebras/Stripes",
            "Unknown Artist/Found Tape",
            "ABBA/Unknown Album",
            "Unknown Artist/Unknown Album",
        ])
    }

    @Test func anArtistsUnknownAlbumSortsAfterTheirTitledAlbums() {
        let context = makeContext()
        let loose = insert(context, title: "Demo", artist: "Band", album: "", year: 1990)
        let record = insert(context, title: "Hit", artist: "Band", album: "Record", year: 2000)

        let artists = LibraryGroups.artists(from: [loose, record])

        #expect(artists.first?.albums.map(\.title) == ["Record", "Unknown Album"])
    }

    @Test func albumYearIsTheMinimumNonNilYearAcrossItsTracks() {
        let context = makeContext()
        let a = insert(context, title: "A", artist: "Band", album: "Anthology", year: 2005)
        let b = insert(context, title: "B", artist: "Band", album: "Anthology", year: nil)
        let c = insert(context, title: "C", artist: "Band", album: "Anthology", year: 2001)

        let albums = LibraryGroups.albums(from: [a, b, c])

        #expect(albums.count == 1)
        #expect(albums[0].year == 2001)
    }

    @Test func albumArtworkIDIsTheFirstNonNilAmongTracksInInputOrder() {
        let context = makeContext()
        // Input-first track has no artwork; input-second has "art-b". Even
        // though disc/track order would put a later-disc track first if it
        // had artwork, "first" here means first in the array passed in.
        let discTwoNoArtwork = insert(
            context, title: "A", artist: "Band", album: "Anthology", discNumber: 2, artworkID: nil
        )
        let discOneWithArtwork = insert(
            context, title: "B", artist: "Band", album: "Anthology", discNumber: 1, artworkID: "art-b"
        )

        let albums = LibraryGroups.albums(from: [discTwoNoArtwork, discOneWithArtwork])

        #expect(albums.count == 1)
        #expect(albums[0].artworkID == "art-b")
    }

    @Test func tracksForIDsPreservesRequestedOrder() throws {
        let context = makeContext()
        let a = insert(context, title: "A", artist: "Band")
        let b = insert(context, title: "B", artist: "Band")
        let c = insert(context, title: "C", artist: "Band")
        try context.save()

        let resolved = LibraryGroups.tracks(
            for: [c.persistentModelID, a.persistentModelID, b.persistentModelID], in: context
        )

        #expect(resolved.map(\.title) == ["C", "A", "B"])
    }

    /// `context.model(for:)` would happily hand back a faulted object for a
    /// deleted track's stale `PersistentIdentifier`, and touching its
    /// properties later would crash. `tracks(for:in:)` should instead fetch
    /// and simply drop IDs that no longer resolve to a live `Track`.
    @Test func tracksForIDsSilentlyDropsAStaleIDForADeletedTrack() throws {
        let context = makeContext()
        let a = insert(context, title: "A", artist: "Band")
        let b = insert(context, title: "B", artist: "Band")
        try context.save()

        let staleID = b.persistentModelID
        context.delete(b)
        try context.save()

        let resolved = LibraryGroups.tracks(for: [staleID, a.persistentModelID], in: context)

        #expect(resolved.map(\.title) == ["A"])
    }
}

@MainActor
private func makeContext() -> ModelContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(for: Schema(LibrarySchema.models), configurations: [configuration])
    return ModelContext(container)
}

@MainActor
@discardableResult
private func insert(
    _ context: ModelContext,
    title: String,
    artist: String,
    album: String = "",
    albumArtist: String? = nil,
    trackNumber: Int? = nil,
    discNumber: Int? = nil,
    year: Int? = nil,
    artworkID: String? = nil
) -> Track {
    let track = Track(
        relativePath: UUID().uuidString,
        title: title,
        artist: artist,
        album: album,
        albumArtist: albumArtist,
        trackNumber: trackNumber,
        discNumber: discNumber,
        year: year,
        duration: 180,
        fileSize: 0,
        fileModified: .now,
        artworkID: artworkID
    )
    context.insert(track)
    return track
}
