import AppFeatures
import CloudFiles
import Domain
import Foundation
import SwiftData
import Testing

/// `PlaylistOps.fileSync` is a static var shared by every `@MainActor` test
/// in this suite (and `PlaylistOpsTests`), and Swift Testing runs tests in
/// this file in parallel. Each test below sets it, does only *synchronous*
/// work (no `await` in between — parallel `@MainActor` tests only interleave
/// at suspension points), then clears it before returning, so no other test
/// ever observes a stray value.
@MainActor
struct PlaylistFileSyncTests {
    @Test func opsWriteFileAfterEachMutation() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let container = try makeContainer()
        let context = container.mainContext
        let store = PlaylistFileStore(directory: directory)
        let sync = PlaylistFileSync(store: store, container: container, defaults: defaults)

        let trackA = makeTrack("a.mp3", title: "Song A", duration: 100)
        let trackB = makeTrack("b.mp3", title: "Song B", duration: 200)
        context.insert(trackA)
        context.insert(trackB)

        PlaylistOps.fileSync = sync
        let playlist = PlaylistOps.create(name: "Road Trip", in: context)
        PlaylistOps.add(trackA, to: playlist, in: context)
        PlaylistOps.add(trackB, to: playlist, in: context)

        let fileURL = directory.appendingPathComponent("Road Trip.m3u8")
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(text.contains("#EXTINF:100,Song A"))
        #expect(text.contains("a.mp3"))
        #expect(text.contains("#EXTINF:200,Song B"))
        #expect(text.contains("b.mp3"))

        PlaylistOps.removeEntries(at: IndexSet([0]), from: playlist, in: context)
        let updatedText = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(!updatedText.contains("a.mp3"))
        #expect(updatedText.contains("b.mp3"))

        PlaylistOps.fileSync = nil
    }

    @Test func renameMovesFile() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let container = try makeContainer()
        let context = container.mainContext
        let store = PlaylistFileStore(directory: directory)
        let sync = PlaylistFileSync(store: store, container: container, defaults: defaults)

        PlaylistOps.fileSync = sync
        let playlist = PlaylistOps.create(name: "Old Name", in: context)
        let oldURL = directory.appendingPathComponent("Old Name.m3u8")
        #expect(FileManager.default.fileExists(atPath: oldURL.path))

        PlaylistOps.rename(playlist, to: "New Name", in: context)
        let newURL = directory.appendingPathComponent("New Name.m3u8")
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))

        PlaylistOps.fileSync = nil
    }

    @Test func deleteRemovesFile() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let container = try makeContainer()
        let context = container.mainContext
        let store = PlaylistFileStore(directory: directory)
        let sync = PlaylistFileSync(store: store, container: container, defaults: defaults)

        PlaylistOps.fileSync = sync
        let playlist = PlaylistOps.create(name: "Doomed", in: context)
        let url = directory.appendingPathComponent("Doomed.m3u8")
        #expect(FileManager.default.fileExists(atPath: url.path))

        PlaylistOps.delete(playlist, in: context)
        #expect(!FileManager.default.fileExists(atPath: url.path))

        PlaylistOps.fileSync = nil
    }

    @Test func roundTripSurvivesStoreWipe() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PlaylistFileStore(directory: directory)

        let containerA = try makeContainer()
        let contextA = containerA.mainContext
        let syncA = PlaylistFileSync(store: store, container: containerA, defaults: defaults)

        let trackA = makeTrack("a.mp3")
        contextA.insert(trackA)

        PlaylistOps.fileSync = syncA
        let playlist = PlaylistOps.create(name: "Mix", in: contextA)
        PlaylistOps.add(trackA, to: playlist, in: contextA)
        // A dangling entry inserted directly (bypassing PlaylistOps, which
        // has no "point at a path with no Track" API), then a no-op reorder
        // to force a fresh export that picks it up as dangling.
        contextA.insert(PlaylistEntry(position: 1, trackPath: "missing.mp3", playlist: playlist))
        try contextA.save()
        PlaylistOps.moveEntries(from: IndexSet(), to: 0, in: playlist, in: contextA)
        PlaylistOps.fileSync = nil

        // Fresh in-memory container, as if the app were reinstalled: the
        // files on disk are the only surviving state. The migration flag is
        // pre-set because this simulates a second launch of this build, not
        // an upgrade from a pre-file-sync version.
        let containerB = try makeContainer()
        defaults.set(true, forKey: "PlaylistFileSync.exportedV1")
        let syncB = PlaylistFileSync(store: store, container: containerB, defaults: defaults)
        syncB.reconcile()

        let contextB = containerB.mainContext
        let playlistsB = try contextB.fetch(FetchDescriptor<Playlist>())
        #expect(playlistsB.map(\.name) == ["Mix"])
        let entriesB = PlaylistOps.sortedEntries(of: playlistsB[0])
        #expect(entriesB.map(\.trackPath) == ["a.mp3", "missing.mp3"])
    }

    @Test func externalEditReplacesEntries() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let container = try makeContainer()
        let context = container.mainContext
        let store = PlaylistFileStore(directory: directory)
        let sync = PlaylistFileSync(store: store, container: container, defaults: defaults)

        let trackA = makeTrack("a.mp3")
        let trackB = makeTrack("b.mp3")
        context.insert(trackA)
        context.insert(trackB)

        PlaylistOps.fileSync = sync
        let playlist = PlaylistOps.create(name: "Mix", in: context)
        PlaylistOps.add(trackA, to: playlist, in: context)
        PlaylistOps.add(trackB, to: playlist, in: context)
        PlaylistOps.fileSync = nil

        // Hand-edit the file as if a user reordered it (or another app
        // wrote it): reversed order, plus a path with no matching Track.
        store.write(name: "Mix", entries: [
            PlaylistFileEntry(trackPath: "b.mp3", title: "B", seconds: 200),
            PlaylistFileEntry(trackPath: "c.mp3", title: "C", seconds: 300),
        ])

        sync.reconcile()

        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        #expect(playlists.count == 1)
        #expect(PlaylistOps.sortedEntries(of: playlists[0]).map(\.trackPath) == ["b.mp3", "c.mp3"])
    }

    @Test func newFileCreatesPlaylist() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let container = try makeContainer()
        let store = PlaylistFileStore(directory: directory)
        let sync = PlaylistFileSync(store: store, container: container, defaults: defaults)

        store.write(name: "External", entries: [PlaylistFileEntry(trackPath: "x.mp3", title: "X", seconds: 10)])
        sync.reconcile()

        let playlists = try container.mainContext.fetch(FetchDescriptor<Playlist>())
        #expect(playlists.map(\.name) == ["External"])
        #expect(PlaylistOps.sortedEntries(of: playlists[0]).map(\.trackPath) == ["x.mp3"])
    }

    @Test func missingFileDeletesPlaylist() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let container = try makeContainer()
        let context = container.mainContext
        let store = PlaylistFileStore(directory: directory)
        let sync = PlaylistFileSync(store: store, container: container, defaults: defaults)

        PlaylistOps.fileSync = sync
        let playlist = PlaylistOps.create(name: "ToRemove", in: context)
        PlaylistOps.fileSync = nil

        _ = playlist
        try FileManager.default.removeItem(at: directory.appendingPathComponent("ToRemove.m3u8"))
        sync.reconcile()

        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        #expect(playlists.isEmpty)
    }

    @Test func danglingPathsSurviveReconcile() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let container = try makeContainer()
        let store = PlaylistFileStore(directory: directory)
        let sync = PlaylistFileSync(store: store, container: container, defaults: defaults)

        store.write(name: "Ghosts", entries: [PlaylistFileEntry(trackPath: "nope/missing.mp3", title: "missing", seconds: -1)])
        sync.reconcile()

        let playlists = try container.mainContext.fetch(FetchDescriptor<Playlist>())
        #expect(playlists.count == 1)
        #expect(PlaylistOps.sortedEntries(of: playlists[0]).map(\.trackPath) == ["nope/missing.mp3"])
    }

    @Test func duplicatePlaylistNamesMergeIntoOneOnReconcile() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let container = try makeContainer()
        let context = container.mainContext
        let store = PlaylistFileStore(directory: directory)
        let sync = PlaylistFileSync(store: store, container: container, defaults: defaults)

        // Nothing stops the app from holding two playlists with the same
        // name (both platforms' "New Playlist" actions mint the same default
        // name every time). One name maps to one file, so reconcile must
        // merge them — and, regression: must not trap building its by-name
        // index on the duplicate key.
        PlaylistOps.fileSync = sync
        PlaylistOps.create(name: "New Playlist", in: context)
        PlaylistOps.create(name: "New Playlist", in: context)
        PlaylistOps.fileSync = nil

        sync.reconcile()

        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        #expect(playlists.map(\.name) == ["New Playlist"])
    }

    @Test func migrationExportsExistingPlaylistsOnce() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let container = try makeContainer()
        let context = container.mainContext
        let store = PlaylistFileStore(directory: directory)

        // Simulate a pre-file-sync (v1) install: a playlist that already
        // exists in SwiftData with no file for it yet, and no `fileSync`
        // hook wired up (as v1 never had one).
        let trackA = makeTrack("a.mp3")
        context.insert(trackA)
        let legacy = Playlist(name: "Legacy")
        context.insert(legacy)
        context.insert(PlaylistEntry(position: 0, trackPath: "a.mp3", playlist: legacy))
        try context.save()

        let sync = PlaylistFileSync(store: store, container: container, defaults: defaults)
        sync.migrateAndReconcile()

        let fileURL = directory.appendingPathComponent("Legacy.m3u8")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        var playlists = try context.fetch(FetchDescriptor<Playlist>())
        #expect(playlists.map(\.name) == ["Legacy"])

        // Second launch: the flag is now set, so migration no longer
        // exports anything — files are the sole truth from here on. Hand-
        // deleting the file and reconciling again proves that: the
        // playlist goes away instead of being re-exported.
        try FileManager.default.removeItem(at: fileURL)
        sync.migrateAndReconcile()

        playlists = try context.fetch(FetchDescriptor<Playlist>())
        #expect(playlists.isEmpty)
    }
}

// MARK: - Helpers

private func makeContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Schema(LibrarySchema.models), configurations: [configuration])
}

private func makeTempDirectory() -> URL {
    return FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}

/// A fresh, isolated `UserDefaults` suite so tests never see each other's
/// (or a previous run's) migration flag. Returns the suite name too, since
/// `removePersistentDomain(forName:)` needs it for cleanup.
private func makeDefaults() -> (UserDefaults, String) {
    let suiteName = UUID().uuidString
    return (UserDefaults(suiteName: suiteName)!, suiteName)
}

private func makeTrack(_ relativePath: String, title: String? = nil, duration: TimeInterval = 180) -> Track {
    Track(
        relativePath: relativePath,
        title: title ?? relativePath,
        duration: duration,
        fileSize: 1000,
        fileModified: Date(timeIntervalSince1970: 0)
    )
}
