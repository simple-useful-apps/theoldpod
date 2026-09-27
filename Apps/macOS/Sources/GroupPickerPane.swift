import Domain
import SwiftData
import SwiftUI

/// The left pane of the Artists and Albums destinations: a search field over
/// a selectable list of groups, with empty and no-match states.
struct GroupPickerPane<Item: Identifiable, Row: View>: View where Item.ID == String {
    let items: [Item]
    let noun: String
    let emptySystemImage: String
    let emptyDescription: String
    let listIdentifier: String
    @Binding var searchText: String
    @Binding var selectedID: String?
    let matches: (Item, String) -> Bool
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        let filtered = items.filter { searchText.isEmpty || matches($0, searchText) }
        VStack {
            TextField("Search \(noun)", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding([.horizontal, .top], 8)
                .onChange(of: searchText) { _, _ in selectedID = nil }
            if items.isEmpty {
                ContentUnavailableView(
                    "No \(noun) Yet",
                    systemImage: emptySystemImage,
                    description: Text(emptyDescription)
                )
            } else {
                List(selection: $selectedID) {
                    ForEach(filtered) { item in
                        row(item).tag(item.id)
                    }
                }
                // Group names also appear in the songs table beside this list,
                // so UI tests scope their lookups to this identifier.
                .accessibilityIdentifier(listIdentifier)
                .overlay {
                    if !searchText.isEmpty, filtered.isEmpty {
                        Text("No matching \(noun.lowercased())").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Which tracks the songs table beside this pane should show: the selected
    /// group's, else every group matching the search, else all tracks.
    static func trackFilter(
        items: [Item],
        selectedID: String?,
        searchText: String,
        matches: (Item, String) -> Bool,
        trackIDs: (Item) -> [PersistentIdentifier]
    ) -> (Track) -> Bool {
        if let selectedID, let item = items.first(where: { $0.id == selectedID }) {
            let ids = Set(trackIDs(item))
            return { ids.contains($0.persistentModelID) }
        }
        guard !searchText.isEmpty else { return { _ in true } }
        let ids = Set(items.filter { matches($0, searchText) }.flatMap(trackIDs))
        return { ids.contains($0.persistentModelID) }
    }
}
