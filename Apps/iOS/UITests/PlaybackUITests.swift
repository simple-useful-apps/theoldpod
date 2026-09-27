import XCTest

/// Covers tap-to-play from the Songs list and the Now Playing sheet's
/// transport (title/artist·album text, advancing to the next track, and
/// dismissal). Mini-player and Now Playing controls carry their own
/// accessibility identifiers (e.g. `miniPlayerTitle`, `nowPlayingTitle`) so
/// assertions never collide with the same track title shown elsewhere on
/// screen (the Songs list row behind the mini bar, etc). Play/Pause state is
/// read from the button's system-provided label ("Play"/"Pause") rather than
/// a state-specific identifier.
final class PlaybackUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTapToPlayShowsMiniPlayerWithPauseControl() {
        let app = XCUIApplication()
        app.launch()

        let row = listText(app, "Fixture One")
        assertExists(row, "Songs list should show Fixture One")
        row.tap()

        let miniBarTitle = app.staticTexts["miniPlayerTitle"]
        assertExists(miniBarTitle, "mini player bar should appear after tapping a song")
        XCTAssertEqual(miniBarTitle.label, "Fixture One", "mini bar should show the now-playing title")

        let playPauseButton = app.buttons["miniPlayerPlayPauseButton"]
        assertExists(playPauseButton)
        XCTAssertEqual(playPauseButton.label, "Pause", "mini bar should show a Pause control while playing")
        attachScreenshot(app, name: "mini-bar-playing-fixture-one")
    }

    func testNowPlayingSheetShowsDetailsAndAdvancesTrack() {
        let app = XCUIApplication()
        app.launch()

        listText(app, "Fixture One").tap()

        let miniBarTitle = app.staticTexts["miniPlayerTitle"]
        assertExists(miniBarTitle)

        // The fixtures are only 3 seconds long, so playback left running
        // would race past Fixture One into Fixture Three on its own before
        // the assertions below run. Pausing immediately freezes the queue
        // position deterministically — `PlayerController.next()` only
        // resumes playback if it was already playing, so once paused,
        // navigating the sheet never advances the track on a wall-clock.
        app.buttons["miniPlayerPlayPauseButton"].tap()
        miniBarTitle.tap()

        let sheetTitle = app.staticTexts["nowPlayingTitle"]
        assertExists(sheetTitle, "Now Playing sheet should present")
        XCTAssertEqual(sheetTitle.label, "Fixture One", "sheet should show the track title")
        let sheetSubtitle = app.staticTexts["nowPlayingSubtitle"]
        assertExists(sheetSubtitle)
        XCTAssertEqual(sheetSubtitle.label, "The Fixtures · Test Tones", "sheet should show \"artist · album\"")
        attachScreenshot(app, name: "now-playing-fixture-one")

        // Sorted title order is Fixture One, Fixture Three, Fixture Two,
        // untagged — tapping Next from Fixture One should land on Fixture
        // Three.
        app.buttons["nowPlayingNextButton"].tap()
        assertExists(sheetTitle, "sheet title should still exist after advancing")
        XCTAssertEqual(sheetTitle.label, "Fixture Three", "Next should advance to Fixture Three")
        attachScreenshot(app, name: "now-playing-fixture-three-before-dismiss")

        let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd, withVelocity: .fast, thenHoldForDuration: 0.1)
        attachScreenshot(app, name: "now-playing-after-dismiss-attempt")
        assertGone(sheetTitle, "dragging down from the top should dismiss the Now Playing sheet")
    }
}
