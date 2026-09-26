import XCTest

/// Covers `SongsListView`'s `.searchable` filter: narrowing to a single
/// match and clearing back to the full library.
final class SearchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSearchNarrowsThenClearRestoresAllSongs() {
        let app = XCUIApplication()
        app.launch()

        let searchField = app.searchFields["Search Songs"]
        assertExists(searchField)
        searchField.tap()
        searchField.typeText("Three")

        assertExists(listText(app, "Fixture Three"), "search for \"Three\" should show Fixture Three")
        XCTAssertFalse(listText(app, "Fixture One").exists, "Fixture One should be filtered out")
        XCTAssertFalse(listText(app, "Fixture Two").exists, "Fixture Two should be filtered out")
        XCTAssertFalse(listText(app, "untagged").exists, "untagged should be filtered out")
        attachScreenshot(app, name: "search-three")

        if searchField.buttons["Clear text"].exists {
            searchField.buttons["Clear text"].tap()
        } else {
            searchField.buttons.firstMatch.tap()
        }

        for title in ["Fixture One", "Fixture Three", "Fixture Two", "untagged"] {
            assertExists(listText(app, title), "clearing search should restore \(title)")
        }
        attachScreenshot(app, name: "search-cleared")
    }
}
