import AppFeatures
import Domain
import Foundation
import SwiftData
import Testing

@MainActor
struct PlaylistOpsTests {
    @Test func createTrimsWhitespaceAndDefaultsEmptyNameToNewPlaylist() throws {
        let context = try makeContext()

        let trimmed = PlaylistOps.create(name: "  Road Trip  ", in: context)
        #expect(trimmed.name == "Road Trip")

        let blank = PlaylistOps.create(name: "   ", in: context)
        #expect(blank.name == "New Playlist")

        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        #expect(playlists.count == 2)
    }

    @Test func renameTrimsWhitespaceAndDefaultsEmptyNameToNewPlaylist() throws {
        let context = try makeContext()
        let playlist = PlaylistOps.create(name: "Original", in: context)

        PlaylistOps.rename(playlist, to: "  Renamed  ", in: context)
        #expect(playlist.name == "Renamed")

        PlaylistOps.rename(playlist, to: "   ", in: context)
        #expect(playlist.name == "New Playlist")
    }

    @Test func addAppendsWithIncreasingPositionsAndAllowsDuplicateTracks() throws {
        let context = try makeContext()
        let playlist = PlaylistOps.create(name: "Mix", in: context)
        let trackA = makeTrack("a.mp3")
        let trackB = makeTrack("b.mp3")
        context.insert(trackA)
        context.insert(trackB)

        PlaylistOps.add(trackA, to: playlist, in: context)
        PlaylistOps.add(trackB, to: playlist, in: context)
        PlaylistOps.add(trackA, to: playlist, in: context) // duplicate, allowed

        let entries = PlaylistOps.sortedEntries(of: playlist)
        #expect(entries.map(\.trackPath) == ["a.mp3", "b.mp3", "a.mp3"])
        #expect(entries.map(\.position) == [0, 1, 2])
    }

    @Test func removeEntriesRenumbersRemainingPositions() throws {
        let context = try makeContext()
        let playlist = PlaylistOps.create(name: "Mix", in: context)
        let tracks = ["a.mp3", "b.mp3", "c.mp3", "d.mp3"].map(makeTrack)
        for track in tracks {
            context.insert(track)
            PlaylistOps.add(track, to: playlist, in: context)
        }

        // Remove indices 0 and 2 ("a.mp3" and "c.mp3"), leaving "b.mp3", "d.mp3".
        PlaylistOps.removeEntries(at: IndexSet([0, 2]), from: playlist, in: context)

        let entries = PlaylistOps.sortedEntries(of: playlist)
        #expect(entries.map(\.trackPath) == ["b.mp3", "d.mp3"])
        #expect(entries.map(\.position) == [0, 1])
    }

    @Test func moveEntriesMatchesArrayMoveSemantics() throws {
        let context = try makeContext()
        let playlist = PlaylistOps.create(name: "Mix", in: context)
        let paths = ["a.mp3", "b.mp3", "c.mp3", "d.mp3", "e.mp3"]
        for path in paths {
            let track = makeTrack(path)
            context.insert(track)
            PlaylistOps.add(track, to: playlist, in: context)
        }

        var expected = paths
        let source = IndexSet([0, 2])
        let destination = 4
        expected.move(fromOffsets: source, toOffset: destination)

        PlaylistOps.moveEntries(from: source, to: destination, in: playlist, in: context)

        let entries = PlaylistOps.sortedEntries(of: playlist)
        #expect(entries.map(\.trackPath) == expected)
        #expect(entries.map(\.position) == Array(0 ..< expected.count))
    }

    @Test func moveEntriesToTheEndMatchesArrayMoveSemantics() throws {
        let context = try makeContext()
        let playlist = PlaylistOps.create(name: "Mix", in: context)
        let paths = ["a.mp3", "b.mp3", "c.mp3"]
        for path in paths {
            let track = makeTrack(path)
            context.insert(track)
            PlaylistOps.add(track, to: playlist, in: context)
        }

        var expected = paths
        let source = IndexSet([0])
        let destination = 3 // move-to-end
        expected.move(fromOffsets: source, toOffset: destination)

        PlaylistOps.moveEntries(from: source, to: destination, in: playlist, in: context)

        let entries = PlaylistOps.sortedEntries(of: playlist)
        #expect(entries.map(\.trackPath) == expected)
    }

    @Test func resolveTracksSkipsDanglingPathsAndPreservesOrder() throws {
        let context = try makeContext()
        let playlist = PlaylistOps.create(name: "Mix", in: context)
        let trackA = makeTrack("a.mp3")
        let trackB = makeTrack("b.mp3")
        context.insert(trackA)
        context.insert(trackB)

        PlaylistOps.add(trackA, to: playlist, in: context)
        PlaylistOps.add(trackB, to: playlist, in: context)

        // Delete the underlying track for "a.mp3" so its entry dangles.
        context.delete(trackA)
        try context.save()

        // Re-add an entry pointing at "b.mp3" so it appears both before and
        // after the dangling entry, to prove order is preserved around it.
        PlaylistOps.add(trackB, to: playlist, in: context)

        let resolved = PlaylistOps.resolveTracks(of: playlist, in: context)
        #expect(resolved.map(\.relativePath) == ["b.mp3", "b.mp3"])
    }

    @Test func deletePlaylistRemovesItsEntriesButNotTracks() throws {
        let context = try makeContext()
        let playlist = PlaylistOps.create(name: "Mix", in: context)
        let trackA = makeTrack("a.mp3")
        let trackB = makeTrack("b.mp3")
        context.insert(trackA)
        context.insert(trackB)
        PlaylistOps.add(trackA, to: playlist, in: context)
        PlaylistOps.add(trackB, to: playlist, in: context)

        PlaylistOps.delete(playlist, in: context)

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
