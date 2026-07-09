import Foundation

/// Watches the `Playlists` directory for changes and emits a debounced
/// signal — no payload, since `PlaylistFileSync` always rescans the whole
/// directory itself rather than trying to diff individual files. Modeled on
/// `LocalFolderWatcher`'s `WatcherEngine` but much simpler: one directory,
/// one `DispatchSource`, no snapshot/diff bookkeeping.
///
/// Directory-level vnode events reliably catch atomic saves (write to a temp
/// file, then rename over the target) — how this app, and most editors,
/// write files. A non-atomic in-place append to an existing file may not
/// trigger an event until the next launch's startup reconcile; that's an
/// accepted limitation, the same one `LocalFolderWatcher` has for MP3s.
public final class PlaylistFolderWatcher: Sendable {
    private let engine: PlaylistWatcherEngine

    public init(directory: URL) {
        engine = PlaylistWatcherEngine(directory: directory)
    }

    public func events() -> AsyncStream<Void> {
        engine.events()
    }

    public func stop() {
        engine.stop()
    }
}

/// All mutable watcher state lives on this actor so the watcher is safe to
/// use from any isolation domain.
private actor PlaylistWatcherEngine {
    private let directory: URL
    private var source: DispatchSourceFileSystemObject?
    private var continuation: AsyncStream<Void>.Continuation?
    private var debounceTask: Task<Void, Never>?
    private var started = false

    init(directory: URL) {
        self.directory = directory
    }

    nonisolated func events() -> AsyncStream<Void> {
        AsyncStream { continuation in
            Task { await self.start(continuation: continuation) }
        }
    }

    nonisolated func stop() {
        Task { await self.stopIsolated() }
    }

    private func start(continuation: AsyncStream<Void>.Continuation) {
        guard !started else { return }
        started = true
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.stopIsolated() }
        }
        // The directory may not exist yet (a fresh library with no
        // playlists); best-effort create it so there's something to watch.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        watch()
    }

    private func stopIsolated() {
        source?.cancel()
        source = nil
        debounceTask?.cancel()
        debounceTask = nil
        continuation?.finish()
        continuation = nil
        // Without this, an `events()` call after `stop()` would see `started`
        // still true and silently return an `AsyncStream` that never emits.
        started = false
    }

    private func watch() {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib, .link],
            queue: DispatchQueue.global(qos: .utility)
        )
        newSource.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.scheduleDebouncedFire() }
        }
        newSource.setCancelHandler {
            close(descriptor)
        }
        newSource.resume()
        source = newSource
    }

    private func scheduleDebouncedFire() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.fire()
        }
    }

    private func fire() {
        continuation?.yield(())
    }
}
