import XCTest

/// Coarse "does the library actually render" smoke test against the seeded
/// Fixtures library: 4 tracks (Fixture One/Two/Three, untagged), 3 albums
/// (Test Tones, Covered, Unknown Album), 3 artists (The Fixtures, Other
/// Artist, Unknown Artist).
final class LibrarySmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAllTabsReachableAndSongsListsAllFixtures() {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        assertExists(tabBar, "tab bar should appear on launch")

        // Songs is the default selection.
        assertExists(app.navigationBars["Songs"], "Songs should be the default tab")
        for title in ["Fixture One", "Fixture Three", "Fixture Two", "untagged"] {
            assertExists(app.staticTexts[title], "Songs tab should list \(title)")
        }
        attachScreenshot(app, name: "songs-tab")

        tabBar.buttons["Albums"].tap()
        assertExists(app.navigationBars["Albums"])
        for album in ["Test Tones", "Covered", "Unknown Album"] {
            assertExists(app.staticTexts[album], "Albums tab should list \(album)")
        }
        attachScreenshot(app, name: "albums-tab")

        tabBar.buttons["Artists"].tap()
        assertExists(app.navigationBars["Artists"])
        for artist in ["The Fixtures", "Other Artist", "Unknown Artist"] {
            assertExists(app.staticTexts[artist], "Artists tab should list \(artist)")
        }
        assertExists(app.staticTexts["1 album · 2 songs"], "The Fixtures summary should read 1 album · 2 songs")
        attachScreenshot(app, name: "artists-tab")

        tabBar.buttons["Playlists"].tap()
        assertExists(app.navigationBars["Playlists"])
        attachScreenshot(app, name: "playlists-tab")

        tabBar.buttons["Songs"].tap()
        assertExists(app.navigationBars["Songs"])
    }
}
