import AppFeatures
import SwiftUI

@main
struct TheOldPodApp: App {
    @State private var coordinator = try? LibraryCoordinator()

    var body: some Scene {
        WindowGroup {
            if let coordinator {
                LibraryRootView(coordinator: coordinator)
                    .modelContainer(coordinator.container)
            } else {
                Text("theoldpod couldn't set up its library folder.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
}
