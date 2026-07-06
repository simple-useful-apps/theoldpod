import CloudFiles
import Foundation
import Testing

/// This test suite runs unsigned, with no iCloud entitlement — the exact
/// environment M5 is designed to degrade gracefully in. `resolve()` must
/// fall back to the local library root every time here, which is a real,
/// runnable assertion (not a stub) about the currently shipping behavior.
struct LibraryLocationTests {
    @Test func resolveFallsBackToLocalRootWithNoICloudEntitlement() async throws {
        let resolved = await LibraryLocation.resolve()
        #expect(resolved.isCloud == false)

        let expectedRoot = try LibraryLocation.defaultRoot()
        #expect(resolved.root == expectedRoot)
    }
}
