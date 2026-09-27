import Foundation
import SwiftData

/// A user-created ordered list of tracks.
@Model
public final class Playlist {
    public var name: String
    public var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.playlist)
    public var entries: [PlaylistEntry]

    public init(name: String, createdAt: Date = .now, entries: [PlaylistEntry] = []) {
        self.name = name
        self.createdAt = createdAt
        self.entries = entries
    }

    public var sortedEntries: [PlaylistEntry] {
        entries.sorted { $0.position < $1.position }
    }
}
