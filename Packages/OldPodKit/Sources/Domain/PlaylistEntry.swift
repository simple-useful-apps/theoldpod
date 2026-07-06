import Foundation
import SwiftData

/// One position in a `Playlist`. Tracks are referenced by path rather than by
/// relationship so playlists survive a rebuild of the library index and can
/// later be exported as plain file-based playlists.
@Model
public final class PlaylistEntry {
    public var position: Int
    public var trackPath: String
    public var playlist: Playlist?

    public init(position: Int, trackPath: String, playlist: Playlist? = nil) {
        self.position = position
        self.trackPath = trackPath
        self.playlist = playlist
    }
}
