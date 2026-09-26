import XCTest

/// Covers the Albums and Artists tabs' navigation into `AlbumDetailView`
/// (exact track membership + Play) and the Artists -> album -> detail chain,
/// plus album Shuffle landing on one of the album's own tracks.
final class AlbumArtistUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAlbumDetailListsExactTracksAndPlays() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Albums"].tap()
        let albumCell = app.staticTexts["Test Tones"]
        assertExists(albumCell)
        albumCell.tap()

        assertExists(app.navigationBars["Test Tones"])
        assertExists(app.staticTexts["Fixture One"], "Test Tones should contain Fixture One")
        assertExists(app.staticTexts["Fixture Two"], "Test Tones should contain Fixture Two")
        XCTAssertFalse(app.staticTexts["Fixture Three"].exists, "Test Tones should not contain Fixture Three")
        assertExists(app.staticTexts["1"], "track 1 should show its track number")
        assertExists(app.staticTexts["2"], "track 2 should show its track number")
        attachScreenshot(app, name: "album-detail-test-tones")

        // Not `app.buttons["Play"]`: the always-present (if disabled)
        // mini-player transport button shares that label whenever nothing
        // is queued yet, making a plain label lookup ambiguous.
        app.buttons["playButton"].tap()

        let miniBarTitle = app.staticTexts["miniPlayerTitle"]
        assertExists(miniBarTitle, "Play should start at track 1, Fixture One")
        XCTAssertEqual(miniBarTitle.label, "Fixture One")
        let playPauseButton = app.buttons["miniPlayerPlayPauseButton"]
        assertExists(playPauseButton)
        XCTAssertEqual(playPauseButton.label, "Pause")
        attachScreenshot(app, name: "album-detail-playing")
    }

    func testArtistDetailNavigatesToAlbum() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Artists"].tap()
        let artistRow = app.staticTexts["The Fixtures"]
        assertExists(artistRow)
        artistRow.tap()

        assertExists(app.navigationBars["The Fixtures"])
        let albumRow = app.staticTexts["Test Tones"]
        assertExists(albumRow, "The Fixtures artist screen should list Test Tones")
        albumRow.tap()

        assertExists(app.navigationBars["Test Tones"])
        assertExists(app.staticTexts["Fixture One"])
        assertExists(app.staticTexts["Fixture Two"])
        attachScreenshot(app, name: "artist-to-album-detail")
    }

    func testShuffleFromAlbumDetailPlaysOneOfItsTracks() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Albums"].tap()
        let albumCell = app.staticTexts["Test Tones"]
        assertExists(albumCell)
        albumCell.tap()
        assertExists(app.navigationBars["Test Tones"])

        app.buttons["shuffleButton"].tap()

        let playPauseButton = app.buttons["miniPlayerPlayPauseButton"]
        assertExists(playPauseButton, "shuffle should start playback")
        XCTAssertEqual(playPauseButton.label, "Pause")
        let miniBarTitle = app.staticTexts["miniPlayerTitle"]
        assertExists(miniBarTitle)
        XCTAssertTrue(
            ["Fixture One", "Fixture Two"].contains(miniBarTitle.label),
            "shuffled playback should show one of Test Tones' own tracks, got \(miniBarTitle.label)"
        )
        attachScreenshot(app, name: "album-shuffle-playing")
    }
}
