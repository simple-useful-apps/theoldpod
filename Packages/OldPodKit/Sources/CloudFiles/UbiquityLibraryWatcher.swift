import Foundation

/// Watches the app's default ubiquity container for MP3 files using
/// `NSMetadataQuery`. All query state lives on the main actor (Apple's
/// documented home for `NSMetadataQuery`); `changes()`/`stop()` are
/// `nonisolated` so this satisfies `LibraryFolderWatching`'s plain (not
/// actor-isolated) requirements, hopping onto the main actor internally —
/// mirroring how `LocalFolderWatcher` wraps its own private engine.
@MainActor
public final class UbiquityLibraryWatcher: LibraryFolderWatching, Sendable {
    private let musicRoot: URL
    private var query: NSMetadataQuery?
    private var observerTokens: [NSObjectProtocol] = []
    private var snapshot: [String: LibraryFileStat] = [:]
    private var continuation: AsyncStream<[LibraryChange]>.Continuation?
    private var started = false

    /// - Parameter containerDocumentsMusicURL: `<ubiquity container>/Documents/Music`.
    ///   Metadata items outside this folder (elsewhere in the container's
    ///   `Documents`) are ignored, since the query scans the whole container.
    public init(containerDocumentsMusicURL: URL) {
        musicRoot = containerDocumentsMusicURL
    }

    public nonisolated func changes() -> AsyncStream<[LibraryChange]> {
        AsyncStream { continuation in
            Task { @MainActor in
                self.start(continuation: continuation)
            }
        }
    }

    public nonisolated func stop() {
        Task { @MainActor in
            self.stopIsolated()
        }
    }

    private func start(continuation: AsyncStream<[LibraryChange]>.Continuation) {
        guard !started else { return }
        started = true
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.stopIsolated() }
        }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE[c] '*.mp3'", NSMetadataItemFSNameKey)
        self.query = query

        let center = NotificationCenter.default
        observerTokens = [
            center.addObserver(
                forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleGathering() }
            },
            center.addObserver(
                forName: .NSMetadataQueryDidUpdate, object: query, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleUpdate() }
            },
        ]

        query.start()
    }

    private func stopIsolated() {
        let center = NotificationCenter.default
        for token in observerTokens {
            center.removeObserver(token)
        }
        observerTokens.removeAll()
        query?.stop()
        query = nil
        continuation?.finish()
        continuation = nil
        // Without this, a `changes()` call after `stop()` would see `started`
        // still true and silently return an `AsyncStream` that never emits.
        started = false
    }

    private func handleGathering() {
        guard let query else { return }
        query.disableUpdates()
        let current = snapshotFromQuery(query)
        query.enableUpdates()
        let changes = LibrarySnapshotDiff.changes(from: [:], to: current, resolveURL: url(for:))
        snapshot = current
        continuation?.yield(changes)
    }

    private func handleUpdate() {
        guard let query else { return }
        query.disableUpdates()
        let current = snapshotFromQuery(query)
        query.enableUpdates()

        let changes = LibrarySnapshotDiff.changes(from: snapshot, to: current, resolveURL: url(for:))
        snapshot = current
        if !changes.isEmpty {
            continuation?.yield(changes)
        }
    }

    private func snapshotFromQuery(_ query: NSMetadataQuery) -> [String: LibraryFileStat] {
        var result: [String: LibraryFileStat] = [:]
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  let path = relativePath(for: url)
            else { continue }

            let size = (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value ?? 0
            let modified = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
                ?? Date(timeIntervalSince1970: 0)
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            // "Downloaded" means a (possibly stale) local copy exists — its
            // bytes are readable, so it counts as downloaded alongside
            // "Current". Only "NotDownloaded" (or unknown) means no bytes.
            let isDownloaded = status == NSMetadataUbiquitousItemDownloadingStatusCurrent
                || status == NSMetadataUbiquitousItemDownloadingStatusDownloaded

            result[path] = LibraryFileStat(size: size, modified: modified, isDownloaded: isDownloaded)
        }
        return result
    }

    /// `nil` for items outside `musicRoot` (the query scans the whole
    /// container's `Documents`, not just our subfolder).
    private func relativePath(for url: URL) -> String? {
        LibraryLocation.relativePath(of: url, under: musicRoot)
    }

    private func url(for path: String) -> URL {
        musicRoot.appendingPathComponent(path)
    }
}
