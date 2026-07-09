import XCTest

/// Covers creating a playlist from the Library menu (`⌘N`), adding a song to
/// it via the Songs table's row context menu, and playing from inside the
/// playlist detail view's header Play button.
///
/// Unlike the sidebar "+" button (`MacRootView.createPlaylist()`, which also
/// selects the new playlist and opens a rename prompt), the Library menu's
/// "New Playlist" command just inserts a playlist named "New Playlist" with
/// no rename opportunity and no selection change — see `TheOldPodApp.swift`'s
/// `LibraryCommands`. That means repeated runs (or prior manual use) can
/// leave more than one playlist sharing that exact name, which would make
/// "the playlist I just created" ambiguous. Rather than a name-based
/// disambiguation, `setUp`/`tearDown` bracket the test by deleting every
/// "New Playlist" sidebar entry (exercising the same sidebar-context-menu
/// delete flow the cleanup itself needs) so the test always starts and ends
/// with none, and the one it creates mid-test is unambiguous throughout.
final class PlaylistUITests: XCTestCase {
    private static let playlistLabel = "New Playlist"

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try MacUITestFixtures.ensureSeeded()
        // Playlist state is reset by the --uitest-reset-playlists launch
        // argument (see launchSettledApp) — no UI-driven cleanup needed.
        app = launchSettledApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testLibraryMenuCreatePlaylistAddSongAndPlayFromIt() {
        let window = mainWindow(app)

        clickMenuItem(app, menu: "Library", item: "New Playlist")
        let playlistRow = sidebarOutline(app).staticTexts[Self.playlistLabel]
        assertExists(playlistRow, "New Playlist should appear in the sidebar after Library > New Playlist")
        attachScreenshot(app, name: "mac-playlist-created")

        selectSidebar(app, "Songs")
        let fixtureTwoRow = window.staticTexts["Fixture Two"]
        assertExists(fixtureTwoRow, "Songs should list Fixture Two")
        let addToPlaylist = openContextMenu(on: fixtureTwoRow, expecting: "Add to Playlist", in: app)
        addToPlaylist.click()

        // Scoped to addToPlaylist's own descendants: the Library menu bar's
        // "New Playlist" command shares this exact label and would
        // otherwise make an app-wide lookup ambiguous.
        let playlistMenuItem = addToPlaylist.menuItems[Self.playlistLabel]
        assertExists(playlistMenuItem, "Add to Playlist submenu should list the new playlist")
        playlistMenuItem.click()

        selectSidebar(app, Self.playlistLabel)
        let entryRow = window.staticTexts["Fixture Two"]
        assertExists(entryRow, "playlist detail should list Fixture Two")
        attachScreenshot(app, name: "mac-playlist-with-song")

        let playButton = app.buttons["playButton"]
        assertExists(playButton, "playlist header should show a Play button")
        playButton.click()

        let barTitle = app.staticTexts["playerBarTitle"]
        assertExists(barTitle, "player bar should show the now-playing title after playlist Play")
        XCTAssertEqual(textValue(barTitle), "Fixture Two", "playlist header Play should start Fixture Two")
        attachScreenshot(app, name: "mac-playlist-playing")
    }

    // MARK: - Cleanup

    // Right-clicks and deletes every sidebar row labeled `name`, one at a
    // time, via the context menu's Delete + the confirmation dialog's
    // destructive button — so a rerun never accumulates stray playlists.
}
