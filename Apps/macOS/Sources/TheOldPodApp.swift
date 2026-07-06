import AppFeatures
import SwiftUI

@main
struct TheOldPodApp: App {
    @State private var coordinator = try? LibraryCoordinator()

    var body: some Scene {
        Window("theoldpod", id: "main") {
            if let coordinator {
                LibraryRootView(coordinator: coordinator)
                    .modelContainer(coordinator.container)
            } else {
                Text("theoldpod couldn't set up its library folder.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .commands {
            if let coordinator {
                PlaybackCommands(coordinator: coordinator)
            }
        }
    }
}

/// Mac menu-bar transport: Space to play/pause, arrow-key skip, shuffle/repeat
/// toggles. M2 is menu-only — the mini-player window and full Now Playing
/// screen arrive in M3.
private struct PlaybackCommands: Commands {
    let coordinator: LibraryCoordinator

    var body: some Commands {
        CommandMenu("Playback") {
            Button("Play/Pause") {
                coordinator.player.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Next Track") {
                coordinator.player.next()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Button("Previous Track") {
                coordinator.player.previous()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Divider()

            Button("Shuffle") {
                coordinator.player.toggleShuffle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button("Repeat") {
                coordinator.player.cycleRepeatMode()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
        }
    }
}
