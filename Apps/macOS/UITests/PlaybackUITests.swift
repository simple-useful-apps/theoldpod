import XCTest

/// Covers the two ways the Songs table starts playback: double-click (a
/// synthesized-event blind spot manual testing can't fully verify — does the
/// `primaryAction` closure actually receive the right clicked row?) and the
/// row context menu's "Play" item, which historically couldn't be driven or
/// verified at all outside a live human click because AppKit context menus
/// aren't part of the normal view hierarchy synthetic CGEvents can target
/// reliably.
final class PlaybackUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDoubleClickRowPlaysIt() {
        let app = launchSettledApp()
        let window = mainWindow(app)

        let row = rowText(window, "Fixture Three")
        assertExists(row, "Songs table should list Fixture Three")
        row.doubleClick()

        let barTitle = app.staticTexts["playerBarTitle"]
        assertExists(barTitle, "player bar should show the now-playing title after double-click")
        XCTAssertEqual(textValue(barTitle), "Fixture Three", "double-clicking Fixture Three should play it")

        let pauseButton = app.buttons["Pause"]
        assertExists(pauseButton, "transport button should read Pause once double-click starts playback")
        attachScreenshot(app, name: "mac-double-click-play")
    }

    func testContextMenuPlayStartsPlayback() {
        let app = launchSettledApp()
        let window = mainWindow(app)

        let row = rowText(window, "Fixture One")
        assertExists(row, "Songs table should list Fixture One")
        openContextMenu(on: row, expecting: "Play", in: app)

        for label in ["Play", "Play Next", "Add to Queue", "Add to Playlist"] {
            assertExists(app.menuItems[label], "context menu should offer \(label)")
        }
        attachScreenshot(app, name: "mac-context-menu-open")

        app.menuItems["Play"].click()

        let barTitle = app.staticTexts["playerBarTitle"]
        assertExists(barTitle, "player bar should show the now-playing title after context menu Play")
        XCTAssertEqual(textValue(barTitle), "Fixture One", "context menu Play should start Fixture One")
        attachScreenshot(app, name: "mac-context-menu-play")
    }
}
