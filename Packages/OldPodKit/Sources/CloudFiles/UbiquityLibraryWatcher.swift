import Foundation

/// Reconciles iCloud's complete metadata view (including remote placeholders)
/// with the files currently materialized under the library root. Metadata-query
/// notifications and local folder events are only invalidations: each emitted
/// batch comes from a complete, error-checked merged snapshot.
@MainActor
public final class UbiquityLibraryWatcher: LibraryFolderWatching {
    private let musicRoot: URL
    private let localWatcher: LocalFolderWatcher
    private var query: NSMetadataQuery?
    private var observerTokens: [NSObjectProtocol] = []
    private var localWatchTask: Task<Void, Never>?
    private var reconciliationTask: Task<Void, Never>?
    private var querySnapshot: [String: LibraryFileStat]?
    private var snapshot: [String: LibraryFileStat] = [:]
    private var continuation: AsyncStream<[LibraryChange]>.Continuation?
    private var refreshWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var reconciliationRequested = false
    private var forceEmissionRequested = false
    private var hasPublishedInitialSnapshot = false
    private var session = 0
    private var started = false

    /// - Parameter containerDocumentsMusicURL: `<ubiquity container>/Documents/Music`.
    ///   Metadata items outside this folder are ignored because the query scans
    ///   the whole container.
    public init(containerDocumentsMusicURL: URL) {
        musicRoot = containerDocumentsMusicURL
        localWatcher = LocalFolderWatcher(root: containerDocumentsMusicURL)
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

    public func refresh() async throws {
        guard let query, !query.isGathering, querySnapshot != nil else {
            throw CocoaError(.fileReadUnknown)
        }
        querySnapshot = snapshotFromQuery(query)

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                refreshWaiters[id] = continuation
                requestReconciliation(forceEmission: true)
            }
        } onCancel: {
            Task { @MainActor in self.cancelRefresh(id: id) }
        }
    }

    private func start(continuation: AsyncStream<[LibraryChange]>.Continuation) {
        guard !started else { return }
        started = true
        session &+= 1
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.stopIsolated() }
        }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(
            format: "%K LIKE[c] '*.mp3' OR %K LIKE[c] '*.m4a'",
            NSMetadataItemFSNameKey,
            NSMetadataItemFSNameKey
        )
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

        localWatchTask = Task { [weak self, localWatcher] in
            for await _ in localWatcher.changes() {
                guard !Task.isCancelled else { break }
                self?.requestReconciliation()
            }
        }
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
        localWatcher.stop()
        localWatchTask?.cancel()
        localWatchTask = nil
        reconciliationTask?.cancel()
        reconciliationTask = nil
        session &+= 1
        for (_, waiter) in refreshWaiters {
            waiter.resume(throwing: CancellationError())
        }
        refreshWaiters.removeAll()
        reconciliationRequested = false
        forceEmissionRequested = false
        querySnapshot = nil
        snapshot = [:]
        hasPublishedInitialSnapshot = false
        continuation?.finish()
        continuation = nil
        started = false
    }

    private func handleGathering() {
        guard let query else { return }
        querySnapshot = snapshotFromQuery(query)
        requestReconciliation()
    }

    private func handleUpdate() {
        guard let query, !query.isGathering, querySnapshot != nil else { return }
        querySnapshot = snapshotFromQuery(query)
        requestReconciliation()
    }

    private func requestReconciliation(forceEmission: Bool = false) {
        guard started, querySnapshot != nil else { return }
        reconciliationRequested = true
        forceEmissionRequested = forceEmissionRequested || forceEmission
        guard reconciliationTask == nil else { return }
        let currentSession = session
        reconciliationTask = Task { [weak self] in
            await self?.runReconciliations(session: currentSession)
        }
    }

    private func runReconciliations(session taskSession: Int) async {
        while reconciliationRequested, !Task.isCancelled {
            reconciliationRequested = false
            guard let queryFiles = querySnapshot else { break }
            do {
                let disk = try await LibraryDiskScanner.scan(root: musicRoot, cloudAware: true)
                guard !Task.isCancelled, started else { break }
                // A notification received during the scan means either source
                // may have changed. Discard this result and scan the latest view.
                if reconciliationRequested { continue }

                let current = mergedSnapshot(query: queryFiles, disk: disk.files)
                let changes = LibrarySnapshotDiff.changes(
                    from: snapshot, to: current, resolveURL: url(for:)
                )
                snapshot = current
                let isInitial = !hasPublishedInitialSnapshot
                hasPublishedInitialSnapshot = true
                if isInitial || forceEmissionRequested || !changes.isEmpty {
                    continuation?.yield(changes)
                }
                forceEmissionRequested = false
                completeRefreshes(with: .success(()))
            } catch is CancellationError {
                break
            } catch {
                guard !reconciliationRequested else { continue }
                forceEmissionRequested = false
                completeRefreshes(with: .failure(error))
            }
        }

        guard taskSession == session else { return }
        reconciliationTask = nil
        if reconciliationRequested, started {
            requestReconciliation()
        }
    }

    private func mergedSnapshot(
        query: [String: LibraryFileStat], disk: [String: LibraryFileStat]
    ) -> [String: LibraryFileStat] {
        var merged = query
        for (path, diskStat) in disk {
            if diskStat.isDownloaded {
                // The file system has the exact bytes the indexer will read;
                // its size and timestamp must therefore drive version checks.
                merged[path] = diskStat
            } else if let queryStat = query[path] {
                merged[path] = LibraryFileStat(
                    size: queryStat.size,
                    modified: queryStat.modified,
                    isDownloaded: false
                )
            } else {
                // Keep locally recognizable placeholders even if Spotlight's
                // metadata query has not caught up yet.
                merged[path] = diskStat
            }
        }
        return merged
    }

    private func snapshotFromQuery(_ query: NSMetadataQuery) -> [String: LibraryFileStat] {
        query.disableUpdates()
        defer { query.enableUpdates() }

        var result: [String: LibraryFileStat] = [:]
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  AudioFileSupport.supports(url),
                  let path = LibraryLocation.relativePath(of: url, under: musicRoot)
            else { continue }

            let size = (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value ?? 0
            let modified = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
                ?? Date(timeIntervalSince1970: 0)
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let isDownloaded = status == NSMetadataUbiquitousItemDownloadingStatusCurrent
                || status == NSMetadataUbiquitousItemDownloadingStatusDownloaded

            result[path] = LibraryFileStat(size: size, modified: modified, isDownloaded: isDownloaded)
        }
        return result
    }

    private func cancelRefresh(id: UUID) {
        refreshWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func completeRefreshes(with result: Result<Void, any Error>) {
        let waiters = refreshWaiters.values
        refreshWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }

    private func url(for path: String) -> URL {
        musicRoot.appendingPathComponent(path)
    }
}
