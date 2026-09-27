import AppFeatures
import AppKit
import PlaybackEngine
import SwiftUI

@main
struct TheOldPodApp: App {
    @State private var coordinator: LibraryCoordinator?
    @State private var setupError: LibrarySetupError?
    @State private var windowActions = MacWindowActions()
    @AppStorage(MiniPlayerView.keepOnTopKey) private var miniPlayerKeepsOnTop = false

    var body: some Scene {
        Window("The Old Pod", id: "main") {
            if let coordinator {
                MacRootView(coordinator: coordinator, windowActions: windowActions)
                    .modelContainer(coordinator.container)
            } else if let setupError {
                // Try Again clears the error, which brings back the
                // ProgressView below and re-runs setup from its task.
                LibrarySetupFailureView(error: setupError) { self.setupError = nil }
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
        .defaultSize(width: 1000, height: 640)
        .commands {
            if let coordinator {
                LibraryCommands(coordinator: coordinator, windowActions: windowActions)
                PlaybackCommands(coordinator: coordinator, windowActions: windowActions)
            }
            // No help book ships with the app; the default item only led to
            // "Help isn't available for The Old Pod".
            CommandGroup(replacing: .help) {}
        }

        // A compact standalone now-playing strip — reachable from the Window
        // menu's default "Mini Player" entry, per the design language's "a
        // persistent now-playing surface is always reachable."
        Window("Mini Player", id: "mini") {
            if let coordinator {
                MiniPlayerView(player: coordinator.player, artworkDirectory: coordinator.artworkDirectory)
            } else {
                // Full-size placeholder: with .windowResizability(.contentSize),
                // a bare ProgressView would shrink a state-restored window to a
                // speck until the library finishes loading.
                ProgressView()
                    .controlSize(.small)
                    .frame(width: MiniPlayerView.size.width, height: MiniPlayerView.size.height)
            }
        }
        .defaultSize(width: MiniPlayerView.size.width, height: MiniPlayerView.size.height)
        .windowResizability(.contentSize)
        .windowLevel(miniPlayerKeepsOnTop ? .floating : .normal)
    }
}

/// Shown when the library can't be set up: the reason, where it was being
/// set up (with a Finder shortcut), and a retry — never a dead end.
private struct LibrarySetupFailureView: View {
    let error: LibrarySetupError
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn\u{2019}t Set Up the Library", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 6) {
                Text(error.reason)
                if let folder = error.libraryFolder {
                    Text(folder.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        } actions: {
            HStack {
                if let folder = error.libraryFolder {
                    Button("Show in Finder") { FinderReveal.reveal(folder) }
                }
                Button("Try Again", action: retry)
                    .keyboardShortcut(.defaultAction)
            }
            // ContentUnavailableView's action area otherwise squeezes the
            // buttons to equal widths, truncating "Show in Finder".
            .fixedSize()
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}

/// Window-level requests that menu commands make of `MacRootView` and the
/// Songs table (the menu bar can't reach into view state directly).
@MainActor
@Observable
final class MacWindowActions {
    /// Drives the main window's Add Music file importer (toolbar "+" and
    /// Library > Add to Library…).
    var isImporterPresented = false
    /// Set by Playback > Go to Current Song. `MacRootView` switches the
    /// sidebar to Songs; that table reveals the playing row and clears this.
    var isRevealingCurrentSong = false

    func revealCurrentSong() {
        isRevealingCurrentSong = true
    }
}

/// Reveals a file (selected) or folder in the Finder.
enum FinderReveal {
    @MainActor
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
    let windowActions: MacWindowActions
    @FocusedValue(\.getInfoAction) private var getInfoAction

    var body: some Commands {
        CommandMenu("Library") {
            // No File menu exists for a `Window` scene (see above), so the
            // classic ⌘O import lives here beside the toolbar "+".
            Button("Add to Library\u{2026}") {
                windowActions.isImporterPresented = true
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("New Playlist") {
                coordinator.playlists.create(name: "New Playlist")
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button("Get Info") {
                getInfoAction?()
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(getInfoAction == nil)
        }
    }
}

/// Mac menu-bar transport: Space to play/pause, arrow-key skip, volume,
/// shuffle/repeat toggles. These drive the same PlayerController as the
/// window's player bar and the Mini Player window.
private struct PlaybackCommands: Commands {
    let coordinator: LibraryCoordinator
    let windowActions: MacWindowActions
    @FocusedValue(\.playSelectionAction) private var playSelectionAction

    private var player: PlayerController {
        coordinator.player
    }

    var body: some Commands {
        CommandMenu("Playback") {
            // Space itself is handled by `SpacebarPlayPause`: the focused
            // Table/List swallows a bare Space before the menu's key
            // equivalent ever sees it. With nothing playing, the monitor
            // routes Space back through this item so it can start the
            // focused table's selection.
            Button("Play/Pause") {
                if player.current == nil, let playSelectionAction {
                    playSelectionAction()
                } else {
                    player.togglePlayPause()
                }
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Next Track") {
                player.next()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Button("Previous Track") {
                player.previous()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Button("Skip Forward 15 Seconds") {
                player.skip(by: 15)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(player.current == nil)

            Button("Skip Back 15 Seconds") {
                player.skip(by: -15)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(player.current == nil)

            Divider()

            Button("Go to Current Song") {
                windowActions.revealCurrentSong()
            }
            .keyboardShortcut("l", modifiers: .command)
            // Books aren't rows in the Songs table.
            .disabled(player.current == nil || player.current?.bookID != nil)

            Divider()

            Button("Volume Up") {
                player.setVolume(player.volume + 0.1)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Button("Volume Down") {
                player.setVolume(player.volume - 0.1)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)

            Divider()

            Button("Shuffle") {
                player.toggleShuffle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button("Repeat") {
                player.cycleRepeatMode()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
        }
    }
}

/// Routes a bare Space to play/pause from anywhere in the main window except
/// text entry. Installed as a local key-down monitor because Tables and Lists
/// consume Space (type-select) before menu key equivalents are consulted, so
/// the Playback menu's shortcut alone never fired.
@MainActor
enum SpacebarPlayPause {
    private static var monitor: Any?

    static func install(player: PlayerController) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49,
                  event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask),
                  let window = event.window,
                  window.attachedSheet == nil,
                  !(window.firstResponder is NSText)
            else { return event }
            if player.current == nil {
                // Nothing to toggle: hand Space to the Playback menu's
                // Play/Pause item, whose action can read the focused song
                // table's selection (a FocusedValue this monitor can't see).
                _ = NSApp.mainMenu?.performKeyEquivalent(with: event)
            } else {
                player.togglePlayPause()
            }
            return nil
        }
    }
}
