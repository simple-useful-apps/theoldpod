import XCTest

/// Covers `SongsTableView`'s `.searchable` filter: narrowing to a single
/// match and clearing back to the full library.
final class SearchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try MacUITestFixtures.ensureSeeded()
    }

    func testSearchNarrowsThenClearRestoresAllSongs() {
        let app = launchSettledApp()
        let window = mainWindow(app)

        let searchField = app.searchFields.firstMatch
        assertExists(searchField, "Songs should expose a search field")
        searchField.click()
        searchField.typeText("three")

        assertExists(window.staticTexts["Fixture Three"], "search for \"three\" should show Fixture Three")
        XCTAssertFalse(window.staticTexts["Fixture One"].exists, "Fixture One should be filtered out")
        XCTAssertFalse(window.staticTexts["Fixture Two"].exists, "Fixture Two should be filtered out")
        XCTAssertFalse(window.staticTexts["untagged"].exists, "untagged should be filtered out")
        attachScreenshot(app, name: "mac-search-three")

        // Select-all + delete rather than a "Clear text" button — macOS
        // search fields expose their clear ("x") control only once text
        // exists and focus has moved there, which is timing-fragile;
        // selecting all and deleting is deterministic regardless of focus
        // history.
        searchField.click()
        searchField.typeKey("a", modifierFlags: .command)
        searchField.typeKey(.delete, modifierFlags: [])

        for title in ["Fixture One", "Fixture Two", "Fixture Three", "untagged"] {
            assertExists(window.staticTexts[title], "clearing search should restore \(title)")
        }
        attachScreenshot(app, name: "mac-search-cleared")
    }
}
