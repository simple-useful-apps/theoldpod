import AppFeatures
import SwiftUI

@main
struct TheOldPodApp: App {
    @State private var coordinator: LibraryCoordinator?
    @State private var setupError: LibrarySetupError?

    var body: some Scene {
        WindowGroup {
            if let coordinator {
                RootTabView(coordinator: coordinator)
                    .modelContainer(coordinator.container)
            } else if let setupError {
                // Try Again clears the error, which brings back the
                // ProgressView below and re-runs setup from its task.
                ContentUnavailableView {
                    Label("Couldn\u{2019}t Set Up the Library", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(setupError.reason)
                } actions: {
                    Button("Try Again") { self.setupError = nil }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
                    .task {
                        switch await LibraryCoordinator.makeResult() {
                        case let .success(made): coordinator = made
                        case let .failure(error): setupError = error
                        }
                    }
            }
        }
    }
}
