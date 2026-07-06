import SwiftUI

/// M3 placeholder for the Playlists tab — playlists themselves land in M4.
public struct PlaylistsPlaceholderView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView(
            "No Playlists Yet",
            systemImage: "list.bullet",
            description: Text("Playlists are coming in the next update.")
        )
    }
}
