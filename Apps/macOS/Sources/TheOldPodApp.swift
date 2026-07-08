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
                LibraryCommands(coordinator: coordinator)
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
                // Full-size placeholder: with .windowResizability(.contentSize),
                // a bare ProgressView would shrink a state-restored window to a
                // ~48×92 speck until the library finishes loading.
                ProgressView()
                    .frame(width: 340, height: 480)
            }
        }
        .defaultSize(width: 340, height: 480)
        .windowResizability(.contentSize)
    }
}

/// Library menu. The sidebar's "+" also creates playlists, but a
/// hover-styled header button never surfaces in the accessibility tree —
/// this menu item (added after exploratory testing) is the discoverable,
/// VoiceOver-reachable path. A plain `Window` scene gets no File menu from
/// SwiftUI, so `.newItem`-anchored CommandGroups have nowhere to land; a
/// dedicated menu it is.
private struct LibraryCommands: Commands {
    let coordinator: LibraryCoordinator

    var body: some Commands {
        CommandMenu("Library") {
            Button("New Playlist") {
                _ = PlaylistOps.create(name: "New Playlist", in: coordinator.container.mainContext)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

/// Mac menu-bar transport: Space to play/pause, arrow-key skip, shuffle/repeat
/// toggles. These drive the same PlayerController as the window's player bar
/// and the Mini Player window.
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
