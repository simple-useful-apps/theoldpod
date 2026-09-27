import XCTest

/// Covers creating a playlist from the Library menu (`⌘N`), adding a song to
/// it via the Songs table's row context menu, and playing from inside the
/// playlist detail view's header Play button.
///
/// Each suite uses a disposable library, so creating or deleting playlists
/// never touches a user's collection.
final class PlaylistUITests: XCTestCase {
    private static let playlistLabel = "New Playlist"

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
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
        let fixtureTwoRow = rowText(window, "Fixture Two")
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
        let entryRow = rowText(window, "Fixture Two")
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
}
