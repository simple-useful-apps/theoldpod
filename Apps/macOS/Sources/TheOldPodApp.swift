import AppFeatures
import SwiftUI

@main
struct TheOldPodApp: App {
    @State private var coordinator: LibraryCoordinator?
    @State private var hasFinishedLoading = false

    var body: some Scene {
        Window("theoldpod", id: "main") {
            if let coordinator {
                MacRootView(coordinator: coordinator)
                    .modelContainer(coordinator.container)
            } else if hasFinishedLoading {
                Text("theoldpod couldn't set up its library folder.")
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
        .defaultSize(width: 1000, height: 640)
        .commands {
            if let coordinator {
                PlaybackCommands(coordinator: coordinator)
            }
        }

        // A standalone Now Playing surface — reachable from the Window menu's
        // default "Mini Player" entry, per the design language's "a persistent
        // now-playing surface is always reachable."
        Window("Mini Player", id: "mini") {
            if let coordinator {
                NowPlayingView(player: coordinator.player, artworkDirectory: coordinator.artworkDirectory)
            } else {
                ProgressView()
            }
        }
        .defaultSize(width: 340, height: 480)
        .windowResizability(.contentSize)
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
