import Foundation

/// Device-local progress; audio files and book folders remain the source of
/// truth for the library. Relative paths survive container moves and reindexing.
struct ListeningHistory: Codable {
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

    var session: Session?
    var books: [String: Bookmark] = [:]
}
