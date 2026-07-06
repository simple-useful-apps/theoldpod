import XCTest

/// Shared helpers for theoldpod's exploratory XCUITest suite. Every test
/// launches its own fresh `XCUIApplication` instance in `setUp`, so state
/// from one test never leaks timing assumptions into another — the library
/// contents (seeded once from `Fixtures/*.mp3`) and any playlists created by
/// a test do persist across launches on disk, which is why playlist tests
/// clean up after themselves.
extension XCTestCase {
    /// The default per-assertion wait: generous enough to absorb simulator
    /// slowness without ever masking a real hang with a bare `sleep`.
    static let uiTimeout: TimeInterval = 10

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
        timeout: TimeInterval = XCTestCase.uiTimeout,
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
        timeout: TimeInterval = XCTestCase.uiTimeout,
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
}
