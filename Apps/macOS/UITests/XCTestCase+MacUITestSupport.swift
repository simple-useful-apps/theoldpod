import XCTest

/// Shared helpers for theoldpod's Mac exploratory XCUITest suite. Mirrors
/// `Apps/iOS/UITests/XCTestCase+UITestSupport.swift`'s conventions
/// (`assertExists`/`assertGone`/`attachScreenshot`, generous
/// `waitForExistence` timeouts instead of sleeps) with the Mac-specific
/// wrinkles: the app state-restores windows (a leftover "Mini Player" window
/// and/or a leftover "New Playlist" sidebar entry may exist from a prior
/// run), and the fixtures library lives in the sandboxed app container
/// rather than the simulator's Documents.
extension XCTestCase {
    /// The default per-assertion wait: generous enough to absorb CI/build
    /// slowness without ever masking a real hang with a bare `sleep`.
    static let macUITimeout: TimeInterval = 10

    /// Attaches a screenshot of `app`'s current state to the test report,
    /// kept regardless of pass/fail so failures are diagnosable after the
    /// fact.
    func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// `element.waitForExistence` wrapped so failures point at the specific
    /// element/query instead of a generic boolean assertion.
    @discardableResult
    func assertExists(
        _ element: XCUIElement,
        timeout: TimeInterval = XCTestCase.macUITimeout,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let exists = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, message().isEmpty ? "Expected \(element) to exist" : message(), file: file, line: line)
        return exists
    }

    /// Waits for `element` to disappear — used to confirm a sheet dismissed
    /// or a filtered row dropped out, without a fixed sleep.
    @discardableResult
    func assertGone(
        _ element: XCUIElement,
        _ message: @autoclosure () -> String = "",
        timeout: TimeInterval = XCTestCase.macUITimeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        let defaultMessage = "Expected \(element) to disappear"
        XCTAssertEqual(result, .completed, message().isEmpty ? defaultMessage : message(), file: file, line: line)
        return result == .completed
    }

    /// Launches a fresh instance and settles it into a known state: closes
    /// the state-restored "Mini Player" window (if state restoration reopened
    /// it) so every test starts pointed at the one main window, and waits for
    /// that main window to be ready.
    @discardableResult
    func launchSettledApp() -> XCUIApplication {
        let app = XCUIApplication()
        // Playlist state resets inside the app at startup — UI-driven cleanup
        // (sidebar context menus) was flaky under AX hit-testing.
        app.launchArguments += ["--uitest-reset-playlists"]
        app.launch()
        closeMiniPlayerIfPresent(app)
        assertExists(mainWindow(app), "main window should exist after launch")
        return app
    }

    /// The app's main library window — identified as "whichever window isn't
    /// titled Mini Player", since the main window's title tracks the sidebar
    /// selection ("Songs"/"Artists"/"Albums"/a playlist name) and so isn't a
    /// fixed string to match on.
    func mainWindow(_ app: XCUIApplication) -> XCUIElement {
        app.windows.matching(NSPredicate(format: "title != %@", "Mini Player")).firstMatch
    }

    /// Right-clicks `element` and waits for `menuItem` to appear, retrying
    /// once after Escape — AppKit context menus occasionally swallow the
    /// first synthetic right-click under test load.
    @discardableResult
    func openContextMenu(on element: XCUIElement, expecting menuItem: String, in app: XCUIApplication) -> XCUIElement {
        element.rightClick()
        var item = app.menuItems[menuItem]
        if !item.waitForExistence(timeout: 4) {
            app.typeKey(.escape, modifierFlags: [])
            element.rightClick()
            item = app.menuItems[menuItem]
            XCTAssertTrue(item.waitForExistence(timeout: 6), "context menu should offer \(menuItem) (after retry)")
        }
        return item
    }

    /// Closes the "Mini Player" window if window-state restoration reopened
    /// it alongside the main window. A leftover key Mini Player window would
    /// otherwise steal focus from clicks intended for the main window.
    func closeMiniPlayerIfPresent(_ app: XCUIApplication) {
        let miniPlayer = app.windows["Mini Player"]
        guard miniPlayer.waitForExistence(timeout: 2) else { return }
        let closeButton = miniPlayer.buttons[XCUIIdentifierCloseWindow]
        if closeButton.waitForExistence(timeout: 2) {
            closeButton.click()
        }
    }

    /// The sidebar's own outline element — `NavigationSplitView` labels its
    /// sidebar column "Sidebar" automatically. Scoping queries to it (rather
    /// than searching the whole app for a label) matters because the
    /// selected destination's name is *also* the window title, and macOS
    /// exposes a window's title as a plain `StaticText` child of the window
    /// itself — so an unscoped `app.staticTexts["Songs"]` becomes ambiguous
    /// (window-title text vs. sidebar row) the moment Songs is selected.
    func sidebarOutline(_ app: XCUIApplication) -> XCUIElement {
        app.outlines["Sidebar"]
    }

    /// Clicks a sidebar row by its visible label ("Songs", "Artists",
    /// "Albums", or a playlist name).
    func selectSidebar(_ app: XCUIApplication, _ label: String) {
        let row = sidebarOutline(app).staticTexts[label]
        assertExists(row, "sidebar should show \(label)")
        row.click()
    }

    /// Opens `menu`'s top-level menu-bar item then clicks the named item
    /// inside it — the standard two-step drill-down XCUITest needs for
    /// AppKit menu bars. The item lookup is scoped to `topLevel`'s own
    /// descendants (not `app.menuBars.menuItems` generally) so it can never
    /// collide with a same-named item somewhere else in the app — e.g. the
    /// Songs row's "Add to Playlist" submenu can list a playlist also named
    /// "New Playlist".
    func clickMenuItem(_ app: XCUIApplication, menu: String, item: String) {
        let topLevel = app.menuBars.menuBarItems[menu]
        assertExists(topLevel, "menu bar should have a \(menu) menu")
        topLevel.click()
        let menuItem = topLevel.menuItems[item]
        assertExists(menuItem, "\(menu) menu should have a \(item) item")
        menuItem.click()
    }

    /// The displayed text of a plain SwiftUI `Text` on macOS. Unlike iOS,
    /// where `StaticText.label` reports the string, AppKit's static-text
    /// accessibility role carries its content in `AXValue` — `.label`
    /// (`AXTitle`) reads back empty. Every assertion on a `Text`'s content in
    /// this suite goes through this helper rather than `.label`.
    func textValue(_ element: XCUIElement) -> String {
        (element.value as? String) ?? ""
    }
}

/// Locates the repo's `Fixtures/` directory of generated test MP3s from this
/// test file's own path, so tests work regardless of the working directory
/// `xcodebuild` is invoked from, and copies them into the Mac app's sandboxed
/// library folder if a previous run (or a fresh container) hasn't seeded it
/// yet. Mirrors `Packages/OldPodKit/Tests/OldPodKitTests/TestFixtures.swift`.
enum MacUITestFixtures {
    /// The four fixture files the whole suite is written against: "Fixture
    /// One"/"Fixture Two" (The Fixtures, Test Tones), "Fixture Three" (Other
    /// Artist, Covered, has artwork), and "untagged" (Unknown Artist/Album).
    static let fileNames = ["cbr-tagged.mp3", "vbr-tagged.mp3", "art-tagged.mp3", "untagged.mp3"]

    static var repoDirectory: URL {
        // This file lives at <repo>/Apps/macOS/UITests/XCTestCase+MacUITestSupport.swift.
        // Walk up to <repo>, then down into Fixtures/.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 {
            url.deleteLastPathComponent()
        }
        return url.appendingPathComponent("Fixtures", isDirectory: true)
    }

    /// The sandboxed Mac app's library folder: `~/Library/Containers/
    /// com.mattreed.theoldpod.mac/Data/Documents/Music`. Never the real
    /// (unsandboxed) user Documents/Music, and never iCloud.
    static var containerMusicDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(
                "Library/Containers/com.mattreed.theoldpod.mac/Data/Documents/Music",
                isDirectory: true
            )
    }

    /// Ensures every fixture file is present in the sandboxed library folder,
    /// copying from the repo's `Fixtures/` directory whenever one is
    /// missing. Safe to call every test run — existing files are left alone.
    static func ensureSeeded() throws {
        let directory = containerMusicDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in fileNames {
            let destination = directory.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            let source = repoDirectory.appendingPathComponent(name)
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }
}
