import XCTest

/// Coarse "does the library actually render" smoke test against the seeded
/// fixtures library: 4 tracks (Fixture One/Two/Three, untagged), reachable
/// through the Songs/Artists/Albums sidebar destinations, with the player
/// bar idle until something plays.
final class LibrarySmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMainWindowSidebarAndSongsListAllFixtures() {
        let app = launchSettledApp()
        let window = mainWindow(app)

        let sidebar = sidebarOutline(app)
        for label in ["Songs", "Artists", "Albums"] {
            assertExists(sidebar.staticTexts[label], "sidebar should show \(label)")
        }

        // Songs is the default selection.
        for title in ["Fixture One", "Fixture Two", "Fixture Three", "untagged"] {
            assertExists(rowText(window, title), "Songs should list \(title)")
        }

        assertExists(app.staticTexts["Not Playing"], "player bar should be idle before anything plays")
        attachScreenshot(app, name: "mac-library-smoke")
    }
}
