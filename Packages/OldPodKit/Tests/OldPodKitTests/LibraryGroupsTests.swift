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
}

@MainActor
private func makeContext() -> ModelContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
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
