import CloudFiles
import Foundation
import Testing

/// Pure diffing logic shared by `LocalFolderWatcher` and
/// `UbiquityLibraryWatcher` — no file system or `NSMetadataQuery` involved.
struct LibrarySnapshotDiffTests {
    private let stat = LibraryFileStat(size: 100, modified: Date(timeIntervalSince1970: 1000), isDownloaded: true)

    @Test func newPathIsAnUpsert() {
        let changes = LibrarySnapshotDiff.changes(
            from: [:], to: ["song.mp3": stat], resolveURL: url(for:)
        )
        #expect(changes == [.upsert(file(path: "song.mp3", stat: stat))])
    }

    @Test func changedSizeIsAnUpsert() {
        let old = ["song.mp3": stat]
        let changedSize = LibraryFileStat(size: 200, modified: stat.modified, isDownloaded: true)
        let changes = LibrarySnapshotDiff.changes(from: old, to: ["song.mp3": changedSize], resolveURL: url(for:))
        #expect(changes == [.upsert(file(path: "song.mp3", stat: changedSize))])
    }

    @Test func changedModifiedDateIsAnUpsert() {
        let old = ["song.mp3": stat]
        let changedDate = LibraryFileStat(
            size: stat.size, modified: stat.modified.addingTimeInterval(1), isDownloaded: true
        )
        let changes = LibrarySnapshotDiff.changes(from: old, to: ["song.mp3": changedDate], resolveURL: url(for:))
        #expect(changes == [.upsert(file(path: "song.mp3", stat: changedDate))])
    }

    @Test func downloadedFlagFlippingIsAnUpsertEvenWithSizeAndDateUnchanged() {
        let old = ["song.mp3": stat]
        let downloaded = LibraryFileStat(size: stat.size, modified: stat.modified, isDownloaded: false)
        let changes = LibrarySnapshotDiff.changes(from: old, to: ["song.mp3": downloaded], resolveURL: url(for:))
        #expect(changes == [.upsert(file(path: "song.mp3", stat: downloaded))])
    }

    @Test func unchangedStatProducesNoChanges() {
        let old = ["song.mp3": stat]
        let changes = LibrarySnapshotDiff.changes(from: old, to: old, resolveURL: url(for:))
        #expect(changes.isEmpty)
    }

    @Test func missingPathIsARemove() {
        let old = ["song.mp3": stat]
        let changes = LibrarySnapshotDiff.changes(from: old, to: [:], resolveURL: url(for:))
        #expect(changes == [.remove(relativePath: "song.mp3")])
    }

    @Test func aMixOfNewChangedUnchangedAndRemovedIsDiffedCorrectly() {
        let old = [
            "unchanged.mp3": stat,
            "changed.mp3": stat,
            "removed.mp3": stat,
        ]
        let changedStat = LibraryFileStat(size: 999, modified: stat.modified, isDownloaded: true)
        let new = [
            "unchanged.mp3": stat,
            "changed.mp3": changedStat,
            "new.mp3": stat,
        ]
        let changes = LibrarySnapshotDiff.changes(from: old, to: new, resolveURL: url(for:))
            .sorted { path(of: $0) < path(of: $1) }
        #expect(changes == [
            .upsert(file(path: "changed.mp3", stat: changedStat)),
            .upsert(file(path: "new.mp3", stat: stat)),
            .remove(relativePath: "removed.mp3"),
        ])
    }

    private func path(of change: LibraryChange) -> String {
        switch change {
        case let .upsert(file): file.relativePath
        case let .remove(relativePath): relativePath
        }
    }

    private func url(for path: String) -> URL {
        URL(fileURLWithPath: "/library").appendingPathComponent(path)
    }

    private func file(path: String, stat: LibraryFileStat) -> LibraryFile {
        LibraryFile(
            relativePath: path, url: url(for: path), size: stat.size, modified: stat.modified,
            isDownloaded: stat.isDownloaded
        )
    }
}
