import SwiftData

/// The full set of persistent model types backing the library store.
public enum LibrarySchema {
    public static let models: [any PersistentModel.Type] = [
        Track.self, Playlist.self, PlaylistEntry.self,
    ]
}
