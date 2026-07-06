import SwiftUI

/// The entry view both apps show once the `LibraryCoordinator` is ready.
/// M1 is deliberately minimal: a single Songs list. The tabbed/sidebar
/// iTunes-style UI arrives in M3.
public struct LibraryRootView: View {
    private let coordinator: LibraryCoordinator

    public init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        NavigationStack {
            SongsListView(libraryRootPath: coordinator.libraryRoot.path)
                .navigationTitle("Songs")
        }
        .task {
            coordinator.start()
        }
    }
}
