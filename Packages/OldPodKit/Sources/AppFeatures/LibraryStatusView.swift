import Domain
import SwiftData
import SwiftUI

/// A check of this device's library, not a promise of cross-device delivery.
struct LibraryStatusView: View {
    let coordinator: LibraryCoordinator
    @Query private var tracks: [Track]

    init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(coordinator.isCloudLibrary ? "iCloud Drive" : "On This Device",
                  systemImage: coordinator.isCloudLibrary ? "icloud" : "folder")
                .font(.headline)
            if let date = coordinator.lastChecked {
                Text("Last checked \(date.formatted(date: .abbreviated, time: .standard))")
            } else {
                Text("Waiting for the library’s first check")
            }
            let pending = tracks.count(where: { !$0.isDownloaded })
            if let error = coordinator.refreshError {
                Text(error).font(.caption)
            }
            if pending > 0 {
                Text("\(pending) files available in iCloud, not downloaded here.")
            }
            Text(coordinator.isCloudLibrary
                ? "Refresh checks for library changes. iCloud manages transfers between devices; files download when you play them."
                : "This library is stored locally and does not sync to your other devices.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Library Folder") {
                Text(coordinator.libraryRoot.path)
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Button {
                Task { await coordinator.refreshLibrary() }
            } label: {
                Label("Refresh Library", systemImage: "arrow.clockwise")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding()
        .frame(width: 340)
    }
}

public struct LibraryStatusButton: View {
    let coordinator: LibraryCoordinator
    @State private var presented = false

    public init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        Button { presented = true } label: {
            Label("Library Status", systemImage: coordinator.isCloudLibrary ? "icloud" : "folder")
        }
        .help("Library location, last check, and refresh")
        .popover(isPresented: $presented) {
            LibraryStatusView(coordinator: coordinator)
                .presentationCompactAdaptation(.popover)
        }
    }
}
