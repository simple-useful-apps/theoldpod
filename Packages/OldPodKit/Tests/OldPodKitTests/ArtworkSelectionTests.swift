@testable import AppFeatures
import CloudFiles
import Foundation
import Testing

struct ArtworkSelectionTests {
    @Test func removalInvalidatesLateConversion() {
        var selection = ArtworkSelection()
        let request = selection.begin()
        selection.remove()
        let accepted1 = selection.finish(request, data: Data([1]))
        #expect(!accepted1)
        #expect(selection.saveSnapshot == .remove)
    }

    @Test func newestSelectionWinsAndStaleErrorsDoNotFinishIt() {
        var selection = ArtworkSelection()
        let old = selection.begin()
        let current = selection.begin()
        let accepted2 = selection.finish(old, data: nil)
        #expect(!accepted2)
        #expect(selection.isProcessing)
        let accepted3 = selection.finish(current, data: Data([2]))
        #expect(accepted3)
        let accepted4 = selection.finish(old, data: Data([1]))
        #expect(!accepted4)
        #expect(selection.change == .replace(Data([2])))
    }

    @Test func saveWaitsForConversionAndCapturesArtwork() {
        var selection = ArtworkSelection()
        #expect(selection.saveSnapshot == .keep)
        let request = selection.begin()
        #expect(selection.saveSnapshot == nil)
        selection.finish(request, data: Data([2]))
        let saved = selection.saveSnapshot
        selection.remove()
        #expect(saved == .replace(Data([2])))
    }

    @Test func currentFailureKeepsPreviousChoiceAndAllowsRetry() {
        var selection = ArtworkSelection()
        selection.remove()
        let request = selection.begin()
        let accepted5 = selection.finish(request, data: nil)
        #expect(accepted5)
        #expect(!selection.isProcessing)
        #expect(selection.saveSnapshot == .remove)
        let retry = selection.begin()
        selection.finish(retry, data: Data([3]))
        #expect(selection.change == .replace(Data([3])))
    }

    @Test func dismissalInvalidatesSuccessAndError() {
        var selection = ArtworkSelection()
        let request = selection.begin()
        selection.invalidate()
        let accepted6 = selection.finish(request, data: Data([1]))
        #expect(!accepted6)
        let accepted7 = selection.finish(request, data: nil)
        #expect(!accepted7)
        #expect(selection.change == .keep)
    }
}
