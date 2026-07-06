import CloudFiles
import Foundation
import Testing

/// `LocalFolderWatcher` reports changes through an `AsyncStream` driven by a
/// real 300ms debounce plus actual filesystem events, so these tests await
/// emissions with a bounded timeout (`ChangeCollector.next`) instead of
/// sleeping for a fixed duration: no bare sleeps as synchronization, and a
/// clear failure instead of a hang if the watcher never fires.
struct LocalFolderWatcherTests {
    @Test func initialSnapshotIncludesNestedFileWithSubdirectoryRelativePath() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try placeFixture("cbr-tagged.mp3", in: root, at: "song1.mp3")
        try placeFixture("vbr-tagged.mp3", in: root, at: "Sub/song2.mp3")

        let watcher = LocalFolderWatcher(root: root)
        defer { watcher.stop() }
        let collector = ChangeCollector(watcher.changes())

        let first = try await collector.next()
        #expect(first.count == 2)
        #expect(upsertedPaths(first) == ["song1.mp3", "Sub/song2.mp3"])
        #expect(first.allSatisfy { if case .upsert = $0 { true } else { false } })
    }

    @Test func addingAFileAfterWatchingStartsEmitsAnUpsert() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try placeFixture("cbr-tagged.mp3", in: root, at: "song1.mp3")

        let watcher = LocalFolderWatcher(root: root)
        defer { watcher.stop() }
        let collector = ChangeCollector(watcher.changes())

        _ = try await collector.next() // initial snapshot

        try placeFixture("vbr-tagged.mp3", in: root, at: "song2.mp3")

        let changes = try await collector.next()
        #expect(upsertedPaths(changes).contains("song2.mp3"))
    }

    @Test func modifyingAFileEmitsAnUpsertForTheSamePath() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try placeFixture("cbr-tagged.mp3", in: root, at: "song.mp3")

        let watcher = LocalFolderWatcher(root: root)
        defer { watcher.stop() }
        let collector = ChangeCollector(watcher.changes())

        _ = try await collector.next() // initial snapshot

        // vbr-tagged.mp3 is a different size than cbr-tagged.mp3, so the
        // rewrite is guaranteed to change the watcher's stat snapshot even if
        // filesystem mtime resolution were coarse.
        let replacement = try Data(contentsOf: TestFixtures.url("vbr-tagged.mp3"))
        try replacement.write(to: root.appendingPathComponent("song.mp3"), options: .atomic)

        let changes = try await collector.next()
        #expect(upsertedPaths(changes).contains("song.mp3"))
    }

    @Test func deletingAFileEmitsARemoveWithItsRelativePath() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try placeFixture("cbr-tagged.mp3", in: root, at: "keep.mp3")
        try placeFixture("vbr-tagged.mp3", in: root, at: "delete-me.mp3")

        let watcher = LocalFolderWatcher(root: root)
        defer { watcher.stop() }
        let collector = ChangeCollector(watcher.changes())

        _ = try await collector.next() // initial snapshot

        try FileManager.default.removeItem(at: root.appendingPathComponent("delete-me.mp3"))

        let changes = try await collector.next()
        #expect(removedPaths(changes).contains("delete-me.mp3"))
        #expect(!upsertedPaths(changes).contains("delete-me.mp3"))
    }

    /// Hardening for a stale `started` flag: after `stop()`, a later
    /// `changes()` call must actually restart the watcher (a fresh initial
    /// snapshot), not silently return a stream that never emits because
    /// `started` was left `true` from the previous run.
    @Test func changesAfterStopRestartsAndEmitsAFreshInitialSnapshot() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try placeFixture("cbr-tagged.mp3", in: root, at: "song1.mp3")

        let watcher = LocalFolderWatcher(root: root)
        let firstCollector = ChangeCollector(watcher.changes())
        let first = try await firstCollector.next()
        #expect(upsertedPaths(first) == ["song1.mp3"])

        watcher.stop()

        let secondCollector = ChangeCollector(watcher.changes())
        defer { watcher.stop() }
        let second = try await secondCollector.next()
        #expect(upsertedPaths(second) == ["song1.mp3"])
    }

    @Test func nonMP3AndHiddenFilesAreIgnored() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let watcher = LocalFolderWatcher(root: root)
        defer { watcher.stop() }
        let collector = ChangeCollector(watcher.changes())

        let first = try await collector.next() // initial snapshot of empty folder
        #expect(first.isEmpty)

        // Add an ignorable text file and an ignorable hidden mp3 alongside a
        // real mp3 in the same debounce window, so a real emission is
        // guaranteed to fire and we can assert the ignorable paths never
        // appear in it (asserting "no event ever arrives" isn't otherwise
        // provable in bounded time).
        try "not audio".write(
            to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8
        )
        try placeFixture("cbr-tagged.mp3", in: root, at: ".hidden.mp3")
        try placeFixture("vbr-tagged.mp3", in: root, at: "visible.mp3")

        let changes = try await collector.next()
        #expect(upsertedPaths(changes) == ["visible.mp3"])
    }
}

// MARK: - Helpers

private func makeTempDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func placeFixture(_ fixtureName: String, in root: URL, at relativePath: String) throws {
    let destination = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(at: TestFixtures.url(fixtureName), to: destination)
}

private func upsertedPaths(_ changes: [LibraryChange]) -> Set<String> {
    Set(changes.compactMap { change in
        if case let .upsert(file) = change { file.relativePath } else { nil }
    })
}

private func removedPaths(_ changes: [LibraryChange]) -> Set<String> {
    Set(changes.compactMap { change in
        if case let .remove(relativePath) = change { relativePath } else { nil }
    })
}

private struct WatcherTimeout: Error, CustomStringConvertible {
    var description: String {
        "Timed out waiting for a LocalFolderWatcher emission."
    }
}

/// Wraps an `AsyncStream` iterator so tests can await the next emission with
/// a bounded timeout instead of racing against the watcher's real debounce
/// with no upper bound. Only ever driven sequentially by a single test, so
/// the lack of internal locking is safe despite the `@unchecked Sendable`.
private final class ChangeCollector: @unchecked Sendable {
    private var iterator: AsyncStream<[LibraryChange]>.Iterator

    init(_ stream: AsyncStream<[LibraryChange]>) {
        iterator = stream.makeAsyncIterator()
    }

    func next(timeout: Duration = .seconds(5)) async throws -> [LibraryChange] {
        let pull = Task { await self.iterator.next() }
        let timeoutGuard = Task {
            try? await Task.sleep(for: timeout)
            pull.cancel()
        }
        defer { timeoutGuard.cancel() }
        guard let result = await pull.value else {
            throw WatcherTimeout()
        }
        return result
    }
}
