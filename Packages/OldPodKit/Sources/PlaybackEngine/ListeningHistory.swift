import Foundation
import Observation
import os

/// Device-local resume state: the last queue and position, plus a bookmark
/// per audiobook. Saved as JSON; relative paths survive container moves and
/// reindexing, and the library folder stays the source of truth.
@MainActor
@Observable
final class ListeningHistory {
    struct Session: Codable {
        var paths: [String]
        var index: Int
        var seconds: Double
        var speed: Float
    }

    struct Bookmark: Codable {
        var path: String
        var seconds: Double
        var speed: Float
        var finished: Bool
    }

    private struct Contents: Codable {
        var session: Session?
        var books: [String: Bookmark] = [:]
    }

    private(set) var saveFailed = false
    private(set) var lastSaved = Date.distantPast
    private var contents = Contents()
    private let url: URL?

    private static let logger = Logger(subsystem: "OldPodKit.PlaybackEngine", category: "ListeningHistory")

    init(url: URL?) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(Contents.self, from: data)
        {
            contents = saved
        }
    }

    var session: Session? {
        contents.session
    }

    func bookmark(for bookID: String) -> Bookmark? {
        contents.books[bookID]
    }

    func record(session: Session, bookmark: (bookID: String, mark: Bookmark)?) {
        contents.session = session
        if let bookmark {
            contents.books[bookmark.bookID] = bookmark.mark
        }
    }

    /// Drops every reference to files that left the library. A session whose
    /// current track was removed resumes on the next survivor from its start.
    func forget(paths: Set<String>, bookIDs: Set<String>) {
        func isGone(_ path: String) -> Bool {
            paths.contains(path) || bookIDs.contains { path.hasPrefix("Audiobooks/\($0)/") }
        }

        for bookID in bookIDs {
            contents.books.removeValue(forKey: bookID)
        }
        contents.books = contents.books.filter { !isGone($0.value.path) }

        guard let session = contents.session else { return }
        let survivors = session.paths.enumerated().filter { !isGone($0.element) }
        guard !survivors.isEmpty else {
            contents.session = nil
            return
        }
        let oldCurrent = session.paths.indices.contains(session.index) ? session.index : 0
        let selected = survivors.first { $0.offset == oldCurrent }
            ?? survivors.first { $0.offset > oldCurrent }
            ?? survivors.last!
        contents.session = Session(
            paths: survivors.map(\.element),
            index: survivors.firstIndex { $0.offset == selected.offset } ?? 0,
            seconds: selected.offset == oldCurrent ? session.seconds : 0,
            speed: session.speed
        )
    }

    func save() {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(contents).write(to: url, options: .atomic)
            saveFailed = false
            lastSaved = Date()
        } catch {
            saveFailed = true
            Self.logger.error("Could not save listening progress: \(error)")
        }
    }
}
