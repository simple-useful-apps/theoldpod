import XCTest

/// Covers creating a playlist, adding a song to it via the song row's
/// context menu, and playing from inside the playlist. Playlists persist on
/// disk across app launches, so this test uses a UUID-suffixed name to stay
/// independent of any leftover state from a previous run, and deletes what
/// it created in `tearDown` (even on failure) so repeated runs don't pile up
/// playlists.
final class PlaylistUITests: XCTestCase {
    private var app: XCUIApplication!
    private var playlistName = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        playlistName = "Road Trip \(UUID().uuidString.prefix(8))"
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        deleteCreatedPlaylistIfPresent()
        app = nil
    }

    func testCreatePlaylistAddSongAndPlayFromIt() {
        app.tabBars.buttons["Playlists"].tap()
        assertExists(app.navigationBars["Playlists"])

        app.buttons["New Playlist"].tap()
        let nameField = app.alerts.textFields.firstMatch
        assertExists(nameField, "New Playlist alert should show a name field")
        nameField.typeText(playlistName)
        app.alerts.buttons["Create"].tap()

        assertExists(app.staticTexts[playlistName], "new playlist should appear in the list")
        attachScreenshot(app, name: "playlist-created")

        app.tabBars.buttons["Songs"].tap()
        let fixtureTwoRow = listText(app, "Fixture Two")
        assertExists(fixtureTwoRow)
        fixtureTwoRow.press(forDuration: 1.0)

        let addToPlaylist = app.buttons["Add to Playlist…"]
        assertExists(addToPlaylist, "context menu should offer Add to Playlist…")
        addToPlaylist.tap()

        assertExists(app.navigationBars["Add to Playlist"], "Add to Playlist sheet should present")
        let playlistOption = app.buttons[playlistName]
        assertExists(playlistOption, "Add to Playlist sheet should list the new playlist")
        playlistOption.tap()

        app.tabBars.buttons["Playlists"].tap()
        assertExists(app.staticTexts[playlistName])
        assertExists(app.staticTexts["1 song"], "playlist should report 1 song after adding Fixture Two")
        attachScreenshot(app, name: "playlist-one-song")

        listText(app, playlistName).tap()
        assertExists(app.navigationBars[playlistName])
        let trackRow = listText(app, "Fixture Two")
        assertExists(trackRow, "playlist detail should list Fixture Two")
        trackRow.tap()

        let miniBarTitle = app.staticTexts["miniPlayerTitle"]
        assertExists(miniBarTitle, "mini bar should play the tapped playlist entry")
        XCTAssertEqual(miniBarTitle.label, "Fixture Two")
        let playPauseButton = app.buttons["miniPlayerPlayPauseButton"]
        assertExists(playPauseButton)
        XCTAssertEqual(playPauseButton.label, "Pause")
        attachScreenshot(app, name: "playlist-song-playing")
    }

    /// Best-effort cleanup: navigates to Playlists and swipe-deletes the row
    /// this test created, if it's still there. Safe to call even when the
    /// test failed partway through (e.g. before the playlist was created).
    private func deleteCreatedPlaylistIfPresent() {
        guard let app else { return }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.buttons["Playlists"].exists else { return }
        tabBar.buttons["Playlists"].tap()

        let row = listText(app, playlistName)
        guard row.waitForExistence(timeout: 3) else { return }
        row.swipeLeft()
        let deleteButton = app.buttons["Delete"]
        if deleteButton.waitForExistence(timeout: 3) {
            deleteButton.tap()
        }
        let confirmButton = app.buttons["Delete \u{201C}\(playlistName)\u{201D}"]
        if confirmButton.waitForExistence(timeout: 3) {
            confirmButton.tap()
        }
    }
}
