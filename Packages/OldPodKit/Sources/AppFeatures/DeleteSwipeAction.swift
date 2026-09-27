import SwiftUI

extension View {
    /// The iOS trailing swipe that asks to delete a library item. Nothing on
    /// macOS, where the context menu carries the same action.
    @ViewBuilder
    func deleteSwipeAction(_ label: String, action: @escaping () -> Void) -> some View {
        #if os(iOS)
            swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(action: action) {
                    Label(label, systemImage: "trash")
                }
                .tint(.red)
            }
        #else
            self
        #endif
    }
}
