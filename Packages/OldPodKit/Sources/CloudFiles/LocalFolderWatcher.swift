import Foundation
import Synchronization

/// Watches a local folder (recursively) for supported audio files using
/// `DispatchSource` file-system-object sources on the root and every
/// subdirectory. File events are debounced and coalesced into a rescan that's
/// diffed against the previous snapshot.
public final class LocalFolderWatcher: LibraryFolderWatching, Sendable {
    private let engine: WatcherEngine

    public init(root: URL) {
        engine = WatcherEngine(root: root)
    }

    public func changes() -> AsyncStream<[LibraryChange]> {
        engine.changes()
    }

    public func stop() {
        engine.stop()
    }

    public func refresh() async throws {
        try await engine.refresh()
    }
}

/// All mutable watcher state lives on this actor so the watcher is safe to
/// use from any isolation domain.
private actor WatcherEngine {
    private let root: URL
    private var snapshot: [String: LibraryFileStat] = [:]
    private var directorySources: [URL: DispatchSourceFileSystemObject] = [:]
    private var continuation: AsyncStream<[LibraryChange]>.Continuation?
    private var debounceTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var scanRequested = false
    private var forceEmissionRequested = false
    private var refreshWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var hasPublishedInitialSnapshot = false
    private var initialRetryCount = 0
    private var session = 0
    private var started = false

    /// `changes()` and `stop()` are synchronous but hop onto the actor in
    /// unstructured Tasks, which run in no guaranteed order. Each call takes a
    /// ticket here, synchronously, and the actor applies them strictly in
    /// ticket order — otherwise `stop(); changes()` could start the new
    /// session first and then have the stale stop tear it down (or be
    /// dropped by the `started` guard), leaving a stream that never emits.
    private nonisolated let tickets = Mutex(0)
    private var nextTicketToApply = 0
    private var pendingOperations: [Int: Operation] = [:]

    private enum Operation {
        case start(AsyncStream<[LibraryChange]>.Continuation)
        case stop
    }

    init(root: URL) {
        self.root = root
    }

    nonisolated func changes() -> AsyncStream<[LibraryChange]> {
        AsyncStream { continuation in
            let ticket = takeTicket()
            Task { await self.apply(.start(continuation), ticket: ticket) }
        }
    }

    nonisolated func stop() {
        let ticket = takeTicket()
        Task { await self.apply(.stop, ticket: ticket) }
    }

    private nonisolated func takeTicket() -> Int {
        tickets.withLock { value in
            defer { value += 1 }
            return value
        }
    }

    private func apply(_ operation: Operation, ticket: Int) {
        pendingOperations[ticket] = operation
        while let next = pendingOperations.removeValue(forKey: nextTicketToApply) {
            nextTicketToApply += 1
            switch next {
            case let .start(continuation):
                start(continuation: continuation)
            case .stop:
                stopIsolated()
            }
        }
    }

    private func start(continuation: AsyncStream<[LibraryChange]>.Continuation) {
        // A second `changes()` while running replaces the old session rather
        // than handing back a stream that would never emit.
        if started { stopIsolated() }
        started = true
        session &+= 1
        let ownSession = session
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            // Only tear down the session this stream belongs to — a stream
            // finished by `stop()` must not stop a newer session.
            Task { await self.stopIfCurrent(session: ownSession) }
        }
        // Keep the root observable even if the initial enumeration fails.
        // A later write can then invalidate the failed scan instead of leaving
        // this watcher permanently silent.
        replaceDirectorySources(with: [root])
        requestScan()
    }

    private func stopIfCurrent(session ownSession: Int) {
        guard started, session == ownSession else { return }
        stopIsolated()
    }

    private func stopIsolated() {
        for (_, source) in directorySources {
            source.cancel()
        }
        directorySources.removeAll()
        debounceTask?.cancel()
        debounceTask = nil
        scanTask?.cancel()
        scanTask = nil
        session &+= 1
        for (_, waiter) in refreshWaiters {
            waiter.resume(throwing: CancellationError())
        }
        refreshWaiters.removeAll()
        scanRequested = false
        forceEmissionRequested = false
        hasPublishedInitialSnapshot = false
        initialRetryCount = 0
        snapshot = [:]
        continuation?.finish()
        continuation = nil
        // Without this, a `changes()` call after `stop()` would see `started`
        // still true and silently return an `AsyncStream` that never emits.
        started = false
    }

    // MARK: - Scanning

    func refresh() async throws {
        guard started else { throw CocoaError(.fileReadUnknown) }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                refreshWaiters[id] = continuation
                requestScan(forceEmission: true)
            }
        } onCancel: {
            Task { await self.cancelRefresh(id: id) }
        }
    }

    private func requestScan(forceEmission: Bool = false) {
        guard started else { return }
        scanRequested = true
        forceEmissionRequested = forceEmissionRequested || forceEmission
        guard scanTask == nil else { return }
        let currentSession = session
        scanTask = Task { [weak self] in
            await self?.runScans(session: currentSession)
        }
    }

    private func runScans(session taskSession: Int) async {
        while scanRequested, !Task.isCancelled {
            scanRequested = false
            do {
                let result = try await LibraryDiskScanner.scan(root: root, cloudAware: false)
                guard !Task.isCancelled, started else { break }
                if scanRequested { continue }

                let old = hasPublishedInitialSnapshot ? snapshot : [:]
                let changes = LibrarySnapshotDiff.changes(
                    from: old, to: result.files, resolveURL: url(for:)
                )
                snapshot = result.files
                let isInitial = !hasPublishedInitialSnapshot
                hasPublishedInitialSnapshot = true
                initialRetryCount = 0
                if isInitial || forceEmissionRequested || !changes.isEmpty {
                    continuation?.yield(changes)
                }
                forceEmissionRequested = false
                replaceDirectorySources(with: result.directories)
                completeRefreshes(with: .success(()))
            } catch is CancellationError {
                break
            } catch {
                guard !scanRequested else { continue }
                if !hasPublishedInitialSnapshot, initialRetryCount < 3 {
                    initialRetryCount += 1
                    do {
                        try await Task.sleep(for: .milliseconds(250 * initialRetryCount))
                    } catch {
                        break
                    }
                    guard started, !Task.isCancelled else { break }
                    scanRequested = true
                    continue
                }
                forceEmissionRequested = false
                completeRefreshes(with: .failure(error))
            }
        }

        guard taskSession == session else { return }
        scanTask = nil
        if scanRequested, started {
            requestScan()
        }
    }

    private func url(for path: String) -> URL {
        root.appendingPathComponent(path)
    }

    // MARK: - Watching

    private func replaceDirectorySources(with directories: [URL]) {
        var updated: [URL: DispatchSourceFileSystemObject] = [:]

        for directory in directories {
            if let existing = directorySources[directory] {
                updated[directory] = existing
            } else if let source = makeSource(for: directory) {
                updated[directory] = source
            }
        }
        for (directory, source) in directorySources where updated[directory] == nil {
            source.cancel()
        }
        directorySources = updated
    }

    private func makeSource(for directory: URL) -> DispatchSourceFileSystemObject? {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib, .link],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.scheduleDebouncedRescan() }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        return source
    }

    private func scheduleDebouncedRescan() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.handleDebouncedFire()
        }
    }

    private func handleDebouncedFire() {
        requestScan()
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
}
