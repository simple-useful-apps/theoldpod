import AppFeatures
import SwiftUI

@main
struct TheOldPodApp: App {
    @State private var coordinator: LibraryCoordinator?
    @State private var hasFinishedLoading = false

    var body: some Scene {
        WindowGroup {
            if let coordinator {
                RootTabView(coordinator: coordinator)
                    .modelContainer(coordinator.container)
            } else if hasFinishedLoading {
                Text("The Old Pod couldn't set up its library folder.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ProgressView()
                    .task {
                        coordinator = await LibraryCoordinator.make()
                        hasFinishedLoading = true
                    }
            }
        }
    }
}
