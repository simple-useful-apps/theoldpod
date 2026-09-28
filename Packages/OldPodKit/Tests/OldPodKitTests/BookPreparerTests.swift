@testable import AppFeatures
import CloudFiles
import Domain
import Foundation
import LibraryStore
import MetadataImport
import SwiftData
import Testing

/// Books are prepared when they reach the index (as iCloud placeholders on
/// iPhone), not when the listener opens them.
@MainActor
struct BookPreparerTests {
    @Test func placeholderChaptersGetTheirLengthsWhenTheBookIsIndexed() async throws {
        let library = try PlaceholderLibrary()
        defer { library.cleanUp() }
        try await library.addPlaceholders([
            ("Audiobooks/Book/01.mp3", "cbr-tagged.mp3"),
            ("Audiobooks/Book/02.mp3", "vbr-tagged.mp3"),
        ])
        #expect(try library.tracks().allSatisfy { $0.duration == 0 && !$0.isDownloaded })

        library.preparer.prepareIncompleteBooks(among: ["Book"])
        await library.preparer.waitUntilIdle()

        let chapters = try library.tracks()
        #expect(chapters.count == 2)
        #expect(chapters.allSatisfy { $0.duration > 0 && $0.isDownloaded })
        #expect(library.preparer.states["Book"] == .ready)
        #expect(library.updates == 1)
    }

    @Test func onlyIncompleteBooksAmongTheChangedOnesArePrepared() async throws {
        let library = try PlaceholderLibrary()
        defer { library.cleanUp() }
        try await library.addPlaceholders([
            ("Audiobooks/Changed/01.mp3", "cbr-tagged.mp3"),
            ("Audiobooks/Untouched/01.mp3", "vbr-tagged.mp3"),
            ("song.mp3", "art-tagged.mp3"),
        ])

        library.preparer.prepareIncompleteBooks(among: ["Changed"])
        await library.preparer.waitUntilIdle()

        let tracks = try library.tracks()
        #expect(tracks.first { $0.relativePath == "Audiobooks/Changed/01.mp3" }?.duration ?? 0 > 0)
        #expect(tracks.first { $0.relativePath == "Audiobooks/Untouched/01.mp3" }?.duration == 0)
        // Songs are never touched by book preparation.
        #expect(tracks.first { $0.relativePath == "song.mp3" }?.duration == 0)
        #expect(library.preparer.states["Untouched"] == nil)

        // A book with nothing missing is not queued again.
        library.preparer.prepareIncompleteBooks(among: ["Changed"])
        await library.preparer.waitUntilIdle()
        #expect(library.updates == 1)
    }

    @Test func anUnreadableChapterMarksTheBookFailed() async throws {
        let library = try PlaceholderLibrary()
        defer { library.cleanUp() }
        try await library.addPlaceholders([("Audiobooks/Broken/01.mp3", nil)])

        library.preparer.prepareIncompleteBooks()
        await library.preparer.waitUntilIdle()

        guard case .failed = library.preparer.states["Broken"] else {
            Issue.record("Expected a failed state, got \(String(describing: library.preparer.states["Broken"]))")
            return
        }
        #expect(try library.tracks().first?.duration == 0)
    }

    @Test func coordinatorPreparesOnlyBooksWithUpsertedChapters() {
        let root = URL(fileURLWithPath: "/library", isDirectory: true)
        func file(_ path: String) -> LibraryChange {
            .upsert(LibraryFile(relativePath: path, url: root.appendingPathComponent(path), size: 1, modified: .distantPast))
        }
        let changes: [LibraryChange] = [
            file("Audiobooks/Added/01.mp3"),
            file("Audiobooks/Added/02.mp3"),
            file("song.mp3"),
            .remove(relativePath: "Audiobooks/Removed/01.mp3"),
        ]
        #expect(LibraryCoordinator.bookIDs(in: changes) == ["Added"])
    }
}

/// A library folder whose files the indexer has seen only as undownloaded
/// iCloud placeholders, as an iPhone first sees a book synced from the Mac.
@MainActor
private final class PlaceholderLibrary {
    let root: URL
    let container: ModelContainer
    let indexer: LibraryIndexer
    private(set) var preparer: BookPreparer!
    private(set) var updates = 0

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(LibrarySchema.models), configurations: [configuration])
        indexer = LibraryIndexer(
            modelContainer: container,
            artwork: ArtworkStore(directory: root.appendingPathComponent(".artwork"))
        )
        preparer = BookPreparer(libraryRoot: root, container: container, indexer: indexer) { [weak self] in
            self?.updates += 1
        }
    }

    /// Copies each fixture (or writes unreadable bytes for `nil`) to its
    /// library path, then indexes it as a placeholder.
    func addPlaceholders(_ files: [(path: String, fixture: String?)]) async throws {
        var changes: [LibraryChange] = []
        for (path, fixture) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            if let fixture {
                try FileManager.default.copyItem(at: TestFixtures.url(fixture), to: url)
            } else {
                try Data("not audio".utf8).write(to: url)
            }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            changes.append(.upsert(LibraryFile(
                relativePath: path,
                url: url,
                size: Int64(values.fileSize ?? 0),
                modified: values.contentModificationDate ?? .distantPast,
                isDownloaded: false
            )))
        }
        await indexer.apply(changes)
    }

    /// A fresh context, so reads see what the indexer saved.
    func tracks() throws -> [Track] {
        try ModelContext(container).fetch(FetchDescriptor<Track>())
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}
