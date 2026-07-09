import XCTest

/// Covers the Artists and Albums sidebar destinations' `HSplitView` filter:
/// picking a row on the left narrows the shared `SongsTableView` on the
/// right to exactly that artist's or album's tracks.
///
/// Two independent tests (each its own fresh launch) rather than one test
/// that visits both destinations: doing a *second* main-sidebar round trip
/// after already clicking into a nested `HSplitView` list (Artists' or
/// Albums' own left-hand list) reproducibly left the sidebar row reporting
/// "Not hittable" even though its reported position never moved and nothing
/// else was on top of it — an accessibility-snapshot hiccup specific to
/// leaving-then-returning-to the outer sidebar within one session. Never
/// needing that second round trip sidesteps it entirely.
final class SidebarFilterUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try MacUITestFixtures.ensureSeeded()
    }

    func testArtistSelectionFiltersTheSongsTable() {
        let app = launchSettledApp()
        let window = mainWindow(app)

        selectSidebar(app, "Artists")
        // Scoped to the artists list (not the whole window): "The Fixtures"
        // is also the Artist column value for two rows in the SongsTableView
        // shown beside it, which would otherwise make the label ambiguous.
        let artistsList = app.outlines["artistsList"]
        assertExists(artistsList, "Artists destination should show the artists list")
        let artistRow = artistsList.staticTexts["The Fixtures"]
        assertExists(artistRow, "Artists list should show The Fixtures")
        artistRow.click()

        assertExists(window.staticTexts["Fixture One"], "The Fixtures filter should include Fixture One")
        assertExists(window.staticTexts["Fixture Two"], "The Fixtures filter should include Fixture Two")
        assertGone(window.staticTexts["Fixture Three"], "The Fixtures filter should exclude Fixture Three")
        assertGone(window.staticTexts["untagged"], "The Fixtures filter should exclude untagged")
        attachScreenshot(app, name: "mac-artist-filter")
    }

    func testAlbumSelectionFiltersTheSongsTable() {
        let app = launchSettledApp()
        let window = mainWindow(app)

        selectSidebar(app, "Albums")
        // Same ambiguity as the artist row in the Artists test above, scoped
        // to the albums list.
        let albumsList = app.outlines["albumsList"]
        assertExists(albumsList, "Albums destination should show the albums list")
        let albumRow = albumsList.staticTexts["Covered"]
        assertExists(albumRow, "Albums list should show Covered")
        albumRow.click()

        assertExists(window.staticTexts["Fixture Three"], "Covered filter should include Fixture Three")
        assertGone(window.staticTexts["Fixture One"], "Covered filter should exclude Fixture One")
        assertGone(window.staticTexts["Fixture Two"], "Covered filter should exclude Fixture Two")
        assertGone(window.staticTexts["untagged"], "Covered filter should exclude untagged")
        attachScreenshot(app, name: "mac-album-filter")
    }
}
