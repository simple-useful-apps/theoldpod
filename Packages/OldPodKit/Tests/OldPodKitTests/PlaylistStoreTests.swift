import AppFeatures
import Domain
import Foundation
import SwiftData
import Testing

@MainActor
struct PlaylistStoreTests {
    @Test func createTrimsWhitespaceAndDefaultsEmptyNameToNewPlaylist() throws {
        let context = try makeContext()
        let store = PlaylistStore(context: context)

        let trimmed = store.create(name: "  Road Trip  ")
        #expect(trimmed.name == "Road Trip")

        let blank = store.create(name: "   ")
        #expect(blank.name == "New Playlist")

        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        #expect(playlists.count == 2)
    }

    @Test func renameTrimsWhitespaceAndDefaultsEmptyNameToNewPlaylist() throws {
        let context = try makeContext()
        let store = PlaylistStore(context: context)
        let playlist = store.create(name: "Original")

        store.rename(playlist, to: "  Renamed  ")
        #expect(playlist.name == "Renamed")

        store.rename(playlist, to: "   ")
        #expect(playlist.name == "New Playlist")
    }

    @Test func addAppendsWithIncreasingPositionsAndAllowsDuplicateTracks() throws {
        let context = try makeContext()
        let store = PlaylistStore(context: context)
        let playlist = store.create(name: "Mix")
        let trackA = makeTrack("a.mp3")
        let trackB = makeTrack("b.mp3")
        context.insert(trackA)
        context.insert(trackB)

        store.add(trackA, to: playlist)
        store.add(trackB, to: playlist)
        store.add(trackA, to: playlist) // duplicate, allowed

        let entries = playlist.sortedEntries
        #expect(entries.map(\.trackPath) == ["a.mp3", "b.mp3", "a.mp3"])
        #expect(entries.map(\.position) == [0, 1, 2])
    }

    @Test func removeEntriesRenumbersRemainingPositions() throws {
        let context = try makeContext()
        let store = PlaylistStore(context: context)
        let playlist = store.create(name: "Mix")
        let tracks = ["a.mp3", "b.mp3", "c.mp3", "d.mp3"].map(makeTrack)
        for track in tracks {
            context.insert(track)
            store.add(track, to: playlist)
        }

        // Remove indices 0 and 2 ("a.mp3" and "c.mp3"), leaving "b.mp3", "d.mp3".
        store.removeEntries(at: IndexSet([0, 2]), from: playlist)

        let entries = playlist.sortedEntries
        #expect(entries.map(\.trackPath) == ["b.mp3", "d.mp3"])
        #expect(entries.map(\.position) == [0, 1])
    }

    @Test func moveEntriesMatchesArrayMoveSemantics() throws {
        let context = try makeContext()
        let store = PlaylistStore(context: context)
        let playlist = store.create(name: "Mix")
        let paths = ["a.mp3", "b.mp3", "c.mp3", "d.mp3", "e.mp3"]
        for path in paths {
            let track = makeTrack(path)
            context.insert(track)
            store.add(track, to: playlist)
        }

        var expected = paths
        let source = IndexSet([0, 2])
        let destination = 4
        expected.move(fromOffsets: source, toOffset: destination)

        store.moveEntries(from: source, to: destination, in: playlist)

        let entries = playlist.sortedEntries
        #expect(entries.map(\.trackPath) == expected)
        #expect(entries.map(\.position) == Array(0 ..< expected.count))
    }

    @Test func moveEntriesToTheEndMatchesArrayMoveSemantics() throws {
        let context = try makeContext()
        let store = PlaylistStore(context: context)
        let playlist = store.create(name: "Mix")
        let paths = ["a.mp3", "b.mp3", "c.mp3"]
        for path in paths {
            let track = makeTrack(path)
            context.insert(track)
            store.add(track, to: playlist)
        }

        var expected = paths
        let source = IndexSet([0])
        let destination = 3 // move-to-end
        expected.move(fromOffsets: source, toOffset: destination)

        store.moveEntries(from: source, to: destination, in: playlist)

        let entries = playlist.sortedEntries
        #expect(entries.map(\.trackPath) == expected)
    }

    @Test func resolveTracksSkipsDanglingPathsAndPreservesOrder() throws {
        let context = try makeContext()
        let store = PlaylistStore(context: context)
        let playlist = store.create(name: "Mix")
        let trackA = makeTrack("a.mp3")
        let trackB = makeTrack("b.mp3")
        context.insert(trackA)
        context.insert(trackB)

        store.add(trackA, to: playlist)
        store.add(trackB, to: playlist)

        // Delete the underlying track for "a.mp3" so its entry dangles.
        context.delete(trackA)
        try context.save()

        // Re-add an entry pointing at "b.mp3" so it appears both before and
        // after the dangling entry, to prove order is preserved around it.
        store.add(trackB, to: playlist)

        let resolved = store.resolveTracks(of: playlist)
        #expect(resolved.map(\.relativePath) == ["b.mp3", "b.mp3"])
    }

    @Test func deletePlaylistRemovesItsEntriesButNotTracks() throws {
        let context = try makeContext()
        let store = PlaylistStore(context: context)
        let playlist = store.create(name: "Mix")
        let trackA = makeTrack("a.mp3")
        let trackB = makeTrack("b.mp3")
        context.insert(trackA)
        context.insert(trackB)
        store.add(trackA, to: playlist)
        store.add(trackB, to: playlist)

        store.delete(playlist)

        let entries = try context.fetch(FetchDescriptor<PlaylistEntry>())
        #expect(entries.isEmpty)

        let tracks = try context.fetch(FetchDescriptor<Track>())
        #expect(tracks.count == 2)
    }
}

private func makeContext() throws -> ModelContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: Schema(LibrarySchema.models), configurations: [configuration])
    return ModelContext(container)
}

private func makeTrack(_ relativePath: String) -> Track {
    Track(
        relativePath: relativePath,
        title: relativePath,
        duration: 180,
        fileSize: 1000,
        fileModified: Date(timeIntervalSince1970: 0)
    )
}
