import SwiftUI

extension View {
    /// The standard "No Results for …" overlay when a search filters a
    /// non-empty collection down to nothing.
    func searchEmptyOverlay(isEmpty: Bool, searchText: String) -> some View {
        overlay {
            if isEmpty, !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}
