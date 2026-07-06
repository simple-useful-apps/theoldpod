import Foundation

/// Watches a local folder (recursively) for `*.mp3` files using
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
}

/// All mutable watcher state lives on this actor so the watcher is safe to
/// use from any isolation domain.
private actor WatcherEngine {
    private let root: URL
    private let fileManager = FileManager.default
    private var snapshot: [String: LibraryFileStat] = [:]
    private var directorySources: [URL: DispatchSourceFileSystemObject] = [:]
    private var continuation: AsyncStream<[LibraryChange]>.Continuation?
    private var debounceTask: Task<Void, Never>?
    private var started = false

    init(root: URL) {
        self.root = root
    }

    nonisolated func changes() -> AsyncStream<[LibraryChange]> {
        AsyncStream { continuation in
            Task { await self.start(continuation: continuation) }
        }
    }

    nonisolated func stop() {
        Task { await self.stopIsolated() }
    }

    private func start(continuation: AsyncStream<[LibraryChange]>.Continuation) {
        guard !started else { return }
        started = true
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.stopIsolated() }
        }
        performInitialScan()
        watchDirectories()
    }

    private func stopIsolated() {
        for (_, source) in directorySources {
            source.cancel()
        }
        directorySources.removeAll()
        debounceTask?.cancel()
        debounceTask = nil
        continuation?.finish()
        continuation = nil
        // Without this, a `changes()` call after `stop()` would see `started`
        // still true and silently return an `AsyncStream` that never emits.
        started = false
    }

    // MARK: - Scanning

    private func performInitialScan() {
        let current = scanFiles()
        let changes = LibrarySnapshotDiff.changes(from: [:], to: current, resolveURL: url(for:))
        snapshot = current
        continuation?.yield(changes)
    }

    private func rescanAndDiff() {
        let current = scanFiles()
        let changes = LibrarySnapshotDiff.changes(from: snapshot, to: current, resolveURL: url(for:))
        snapshot = current
        if !changes.isEmpty {
            continuation?.yield(changes)
        }
    }

    private func url(for path: String) -> URL {
        root.appendingPathComponent(path)
    }

    private func scanFiles() -> [String: LibraryFileStat] {
        var result: [String: LibraryFileStat] = [:]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return result }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
            ) else { continue }
            if values.isDirectory == true { continue }
            guard url.pathExtension.lowercased() == "mp3" else { continue }
            // The enumerator only ever yields URLs under `root`, so this
            // should never actually be nil — but skip rather than crash if
            // it somehow were.
            guard let path = LibraryLocation.relativePath(of: url, under: root) else { continue }

            let stat = LibraryFileStat(
                size: Int64(values.fileSize ?? 0),
                modified: values.contentModificationDate ?? Date(timeIntervalSince1970: 0),
                isDownloaded: true
            )
            result[path] = stat
        }
        return result
    }

    private func allDirectories() -> [URL] {
        var directories = [root]
        guard let enumerator = fileManager.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return directories }

        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                directories.append(url)
            }
        }
        return directories
    }

    // MARK: - Watching

    private func watchDirectories() {
        let directories = allDirectories()
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
        rescanAndDiff()
        watchDirectories()
    }
}
