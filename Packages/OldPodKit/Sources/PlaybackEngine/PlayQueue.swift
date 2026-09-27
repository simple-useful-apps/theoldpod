import Domain
import Foundation

/// An immutable, `Sendable` snapshot of a `Track` suitable for handing to
/// `AVQueuePlayer` and for crossing actor boundaries — `Track` itself is a
/// `@Model` and must never leave the main actor.
public struct PlayableTrack: Sendable, Equatable, Identifiable {
    public var id: String {
        relativePath
    }

    public let relativePath: String
    public let url: URL
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    public let artworkID: String?
    public let isDownloaded: Bool

    public var bookID: String? {
        AudiobookPath.bookID(for: relativePath)
    }

    public var displayArtist: String {
        artist.isEmpty ? "Unknown Artist" : artist
    }

    public var subtitle: String {
        if bookID != nil { return artist.isEmpty ? album : "\(artist) · \(album)" }
        return "\(displayArtist) · \(album.isEmpty ? "Unknown Album" : album)"
    }

    public init(
        relativePath: String,
        url: URL,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        artworkID: String?,
        isDownloaded: Bool = true
    ) {
        self.relativePath = relativePath
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkID = artworkID
        self.isDownloaded = isDownloaded
    }

    /// Snapshots a SwiftData `Track` (main-actor only) into a value that can
    /// safely cross into `PlaybackEngine`/`AVFoundation` code. `libraryRoot`
    /// resolves the track's `relativePath` into a playable file URL.
    @MainActor
    public init(track: Track, libraryRoot: URL) {
        relativePath = track.relativePath
        url = libraryRoot.appendingPathComponent(track.relativePath)
        title = track.title
        artist = track.artist
        album = track.bookID ?? track.album
        duration = track.duration
        artworkID = track.artworkID
        isDownloaded = track.isDownloaded
    }
}

public enum RepeatMode: String, Sendable, CaseIterable {
    case off, all, one
}

/// The app-owned play order: which tracks are queued, whether they're
/// shuffled, and where playback currently sits. Pure value type so its
/// behavior is exhaustively unit-testable without any `AVFoundation` state.
public struct PlayQueue: Sendable, Equatable {
    public enum RemovalOutcome: Sendable, Equatable {
        case unchanged
        case currentPreserved
        case currentReplaced
        case emptied
    }

    public private(set) var items: [PlayableTrack]
    public private(set) var currentIndex: Int?
    public private(set) var isShuffled: Bool

    /// The insertion order, kept around so `setShuffled(false, ...)` can
    /// restore it. Tracks appended/inserted while shuffled are appended to
    /// the tail here too, which is a reasonable, consistent rule since
    /// original order only matters for restoring after an un-shuffle.
    private var originalOrder: [PlayableTrack]

    public var current: PlayableTrack? {
        guard let currentIndex else { return nil }
        return items[currentIndex]
    }

    public init() {
        items = []
        currentIndex = nil
        isShuffled = false
        originalOrder = []
    }

    /// What should preload next in the player, honoring `repeatMode`.
    /// `.one` repeats the current track itself; `.all` wraps to the head;
    /// `.off` returns nil once the current item is the last one.
    public func upNext(repeatMode: RepeatMode) -> PlayableTrack? {
        guard let currentIndex else { return nil }
        switch repeatMode {
        case .one:
            return items[currentIndex]
        case .all:
            let nextIndex = (currentIndex + 1) % items.count
            return items[nextIndex]
        case .off:
            let nextIndex = currentIndex + 1
            return nextIndex < items.count ? items[nextIndex] : nil
        }
    }

    public mutating func replace(with tracks: [PlayableTrack], startingAt index: Int) {
        items = tracks
        originalOrder = tracks
        isShuffled = false
        currentIndex = tracks.indices.contains(index) ? index : (tracks.isEmpty ? nil : 0)
    }

    /// Turning shuffle ON keeps the currently playing track first and
    /// shuffles the rest after it (Fisher-Yates, using the injected
    /// generator so tests are deterministic). Turning OFF restores the
    /// original insertion order with `currentIndex` following the current
    /// track.
    public mutating func setShuffled(_ on: Bool, using generator: inout some RandomNumberGenerator) {
        guard on != isShuffled else { return }
        guard !items.isEmpty else {
            isShuffled = on
            return
        }

        if on {
            let currentTrack = current
            var rest = items
            var currentPosition: Int?
            if let currentTrack, let index = rest.firstIndex(of: currentTrack) {
                currentPosition = index
            }
            if let currentPosition {
                rest.remove(at: currentPosition)
            }
            rest.shuffle(using: &generator)
            if let currentTrack {
                items = [currentTrack] + rest
                currentIndex = 0
            } else {
                items = rest
            }
            isShuffled = true
        } else {
            let currentTrack = current
            items = originalOrder
            isShuffled = false
            if let currentTrack {
                currentIndex = items.firstIndex(of: currentTrack)
            }
        }
    }

    /// Natural track-end advance (the item finished playing on its own).
    /// `.one` stays on the current track; `.all` wraps to the head; `.off`
    /// returns nil once past the last item, leaving the queue parked at the
    /// tail.
    public mutating func advanceAfterItemEnd(repeatMode: RepeatMode) -> PlayableTrack? {
        guard let currentIndex else { return nil }
        switch repeatMode {
        case .one:
            return items[currentIndex]
        case .all:
            let nextIndex = (currentIndex + 1) % items.count
            self.currentIndex = nextIndex
            return items[nextIndex]
        case .off:
            let nextIndex = currentIndex + 1
            guard nextIndex < items.count else { return nil }
            self.currentIndex = nextIndex
            return items[nextIndex]
        }
    }

    /// A user-initiated skip forward. Unlike `advanceAfterItemEnd`, this
    /// always moves — `.one` does not pin playback to the current track.
    /// Wraps only under `.all`; `.off` returns nil once past the tail.
    public mutating func skipNext(repeatMode: RepeatMode) -> PlayableTrack? {
        guard let currentIndex else { return nil }
        let nextIndex = currentIndex + 1
        if nextIndex < items.count {
            self.currentIndex = nextIndex
            return items[nextIndex]
        }
        switch repeatMode {
        case .all:
            self.currentIndex = 0
            return items.first
        case .one, .off:
            return nil
        }
    }

    /// A user-initiated skip backward. Always moves back one item. Wraps
    /// under `.all`; under `.off`/`.one` at the head it stays put and
    /// returns the (unchanged) current track.
    public mutating func skipPrevious(repeatMode: RepeatMode) -> PlayableTrack? {
        guard let currentIndex else { return nil }
        let previousIndex = currentIndex - 1
        if previousIndex >= 0 {
            self.currentIndex = previousIndex
            return items[previousIndex]
        }
        switch repeatMode {
        case .all:
            let lastIndex = items.count - 1
            self.currentIndex = lastIndex
            return items[lastIndex]
        case .one, .off:
            return items[currentIndex]
        }
    }

    /// Inserts `track` right after the current item so it plays next. If the
    /// queue is empty this behaves like `replace(with: [track], startingAt: 0)`.
    public mutating func playNext(_ track: PlayableTrack) {
        guard let currentIndex else {
            replace(with: [track], startingAt: 0)
            return
        }
        items.insert(track, at: currentIndex + 1)
        originalOrder.append(track)
    }

    public mutating func append(_ track: PlayableTrack) {
        items.append(track)
        originalOrder.append(track)
        if currentIndex == nil {
            currentIndex = 0
        }
    }

    /// Replaces stale index snapshots (notably zero-duration iCloud/book
    /// placeholders) without changing queue order or the selected occurrence.
    public mutating func refreshMetadata(from available: [PlayableTrack]) {
        let byPath = Dictionary(available.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        items = items.map { byPath[$0.relativePath] ?? $0 }
        originalOrder = originalOrder.map { byPath[$0.relativePath] ?? $0 }
    }

    /// Removes every occurrence of an exact path, plus every chapter below
    /// the requested book folders. If the current item is removed, the queue
    /// parks on the nearest following survivor (or the preceding tail).
    @discardableResult
    public mutating func remove(
        relativePaths: Set<String>,
        bookIDs: Set<String> = []
    ) -> RemovalOutcome {
        func shouldRemove(_ track: PlayableTrack) -> Bool {
            if relativePaths.contains(track.relativePath) { return true }
            return bookIDs.contains { bookID in
                track.relativePath.hasPrefix("Audiobooks/\(bookID)/")
            }
        }

        let indexedSurvivors = items.enumerated().filter { !shouldRemove($0.element) }
        guard indexedSurvivors.count != items.count else { return .unchanged }

        originalOrder.removeAll(where: shouldRemove)
        guard !indexedSurvivors.isEmpty else {
            items = []
            currentIndex = nil
            return .emptied
        }

        let oldCurrentIndex = currentIndex
        let currentSurvived = oldCurrentIndex.map { index in
            indexedSurvivors.contains { $0.offset == index }
        } ?? false
        let selectedOldIndex: Int = if let oldCurrentIndex, currentSurvived {
            oldCurrentIndex
        } else if let oldCurrentIndex,
                  let following = indexedSurvivors.first(where: { $0.offset > oldCurrentIndex })
        {
            following.offset
        } else {
            indexedSurvivors.last!.offset
        }

        items = indexedSurvivors.map(\.element)
        currentIndex = indexedSurvivors.firstIndex { $0.offset == selectedOldIndex }
        return currentSurvived ? .currentPreserved : .currentReplaced
    }
}
