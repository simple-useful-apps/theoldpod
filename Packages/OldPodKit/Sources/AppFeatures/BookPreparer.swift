import CloudFiles
import Domain
import Foundation
import LibraryStore
import MetadataImport
import Observation
import SwiftData

public enum BookPreparationState: Sendable, Equatable {
    case preparing(completed: Int, total: Int)
    case ready
    case failed(String)
}

/// Loads the metadata a book's chapters are still missing (undownloaded
/// iCloud placeholders, unread durations) when the user opens the book.
/// Reads run three files at a time, and the indexer re-checks each file's
/// version before applying a result, so a slow read cannot resurrect a
/// chapter that was deleted meanwhile.
@MainActor
@Observable
public final class BookPreparer {
    public private(set) var states: [String: BookPreparationState] = [:]

    private let libraryRoot: URL
    private let container: ModelContainer
    private let indexer: LibraryIndexer
    private let onChaptersUpdated: () -> Void

    init(libraryRoot: URL, container: ModelContainer, indexer: LibraryIndexer, onChaptersUpdated: @escaping () -> Void) {
        self.libraryRoot = libraryRoot
        self.container = container
        self.indexer = indexer
        self.onChaptersUpdated = onChaptersUpdated
    }

    public func prepare(named name: String, relativePaths: [String]) async {
        guard !relativePaths.isEmpty else { return }
        let requested = Set(relativePaths)
        guard let tracks = try? container.mainContext.fetch(FetchDescriptor<Track>()) else { return }
        let missing = tracks
            .filter { requested.contains($0.relativePath) && (!$0.isDownloaded || $0.duration <= 0) }
            .map(\.relativePath)
        guard !missing.isEmpty else {
            states[name] = .ready
            return
        }

        states[name] = .preparing(completed: 0, total: missing.count)
        var completed = 0
        var failures: [String] = []
        for batch in missing.chunks(of: 3) {
            guard !Task.isCancelled else { return }
            let libraryRoot = libraryRoot
            let refreshes = await withTaskGroup(of: LibraryMetadataRefresh?.self) { group in
                for path in batch {
                    group.addTask { await Self.readMetadata(of: path, in: libraryRoot) }
                }
                var loaded: [LibraryMetadataRefresh] = []
                for await refresh in group {
                    if let refresh { loaded.append(refresh) }
                }
                return loaded
            }
            guard !Task.isCancelled else { return }
            let updated = await indexer.applyMetadataRefreshes(refreshes)
            failures.append(contentsOf: batch.filter { !updated.contains($0) })
            completed += batch.count
            states[name] = .preparing(completed: completed, total: missing.count)
        }

        states[name] = failures.isEmpty
            ? .ready
            : .failed("Some chapter details aren’t available yet. Check your connection and try again.")
        onChaptersUpdated()
    }

    /// Requests the download and reads the file once it has a duration,
    /// retrying briefly while iCloud delivers the bytes.
    private nonisolated static func readMetadata(of path: String, in libraryRoot: URL) async -> LibraryMetadataRefresh? {
        let url = libraryRoot.appendingPathComponent(path)
        DownloadRequester.requestDownload(of: url)
        for attempt in 0 ..< 4 {
            if Task.isCancelled { return nil }
            if let before = FileVersion.current(at: url),
               let metadata = try? await MetadataReader.read(from: url), metadata.duration > 0,
               FileVersion.current(at: url) == before
            {
                return LibraryMetadataRefresh(relativePath: path, url: url, metadata: metadata, fileVersion: before)
            }
            if attempt < 3 { try? await Task.sleep(for: .milliseconds(750)) }
        }
        return nil
    }
}

private extension Array {
    func chunks(of size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
