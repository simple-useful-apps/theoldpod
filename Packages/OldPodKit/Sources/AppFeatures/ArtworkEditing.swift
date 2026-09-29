#if os(macOS)
    import AppKit
    import CloudFiles
    import Domain
    import SwiftUI
    import UniformTypeIdentifiers

    public struct ArtworkUpdateFailure: Sendable, Equatable {
        public let fileName: String
        public let message: String
    }

    /// What applying one picture to an album or book did, file by file.
    public struct ArtworkUpdateResult: Sendable, Equatable {
        public var updatedCount = 0
        /// Files still in iCloud, left with their old artwork.
        public var skippedCount = 0
        public var failures: [ArtworkUpdateFailure] = []
    }

    /// One file an album- or book-wide artwork change will touch.
    public struct ArtworkFile: Sendable, Hashable {
        public let relativePath: String
        public let isDownloaded: Bool
        public let hasArtwork: Bool

        @MainActor
        public init(track: Track) {
            relativePath = track.relativePath
            isDownloaded = track.isDownloaded
            hasArtwork = track.artworkID != nil
        }
    }

    /// Choose Artwork… / Remove Artwork for a whole album or book.
    public struct ArtworkRequest: Identifiable, Sendable {
        public enum Action: Sendable {
            case choose, remove
        }

        public let title: String
        public let files: [ArtworkFile]
        public let action: Action

        public var id: String {
            "\(action):\(title)"
        }

        @MainActor
        public init(title: String, tracks: [Track], action: Action) {
            self.title = title
            files = tracks.map(ArtworkFile.init(track:))
            self.action = action
        }
    }

    /// The Mac's image picker. An open panel rather than `fileImporter`,
    /// which misbehaves when a view tree already has one (Books, the main
    /// window's Add Music).
    @MainActor
    public enum ArtworkPicker {
        public static func chooseImage() async -> URL? {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.message = "Choose a picture to use as artwork."
            panel.prompt = "Choose"
            return await withCheckedContinuation { continuation in
                panel.begin { response in
                    continuation.resume(returning: response == .OK ? panel.url : nil)
                }
            }
        }
    }

    public struct ArtworkMenuItems: View {
        let title: String
        let tracks: [Track]
        @Binding var request: ArtworkRequest?

        public init(title: String, tracks: [Track], request: Binding<ArtworkRequest?>) {
            self.title = title
            self.tracks = tracks
            _request = request
        }

        public var body: some View {
            Button("Choose Artwork\u{2026}", systemImage: "photo") {
                request = ArtworkRequest(title: title, tracks: tracks, action: .choose)
            }
            Button("Remove Artwork", systemImage: "rectangle.slash") {
                request = ArtworkRequest(title: title, tracks: tracks, action: .remove)
            }
            .disabled(!tracks.contains { $0.artworkID != nil })
        }
    }

    private struct ArtworkRequestModifier: ViewModifier {
        @Binding var request: ArtworkRequest?
        let coordinator: LibraryCoordinator
        @State private var pendingRemoval: ArtworkRequest?
        @State private var problem: ArtworkProblem?

        func body(content: Content) -> some View {
            content
                .onChange(of: request?.id) { _, _ in
                    guard let pending = request else { return }
                    request = nil
                    switch pending.action {
                    case .choose:
                        Task { await choose(for: pending) }
                    case .remove:
                        pendingRemoval = pending
                    }
                }
                .confirmationDialog(
                    "Remove the artwork from \(pendingRemoval?.title ?? "")?",
                    isPresented: $pendingRemoval.isPresent,
                    titleVisibility: .visible,
                    presenting: pendingRemoval
                ) { pending in
                    Button("Remove Artwork", role: .destructive) {
                        pendingRemoval = nil
                        Task { await apply(.remove, to: pending) }
                    }
                    Button("Cancel", role: .cancel) { pendingRemoval = nil }
                } message: { pending in
                    Text(pending.files.count == 1
                        ? "The picture will be removed from its file."
                        : "The picture will be removed from all \(pending.files.count) files.")
                }
                .alert(problem?.title ?? "", isPresented: $problem.isPresent, presenting: problem) { _ in
                    Button("OK", role: .cancel) {}
                } message: { problem in
                    Text(problem.message)
                }
        }

        private func choose(for pending: ArtworkRequest) async {
            guard let url = await ArtworkPicker.chooseImage() else { return }
            do {
                let data = try await Task.detached { try ArtworkImagePreparer.jpegData(contentsOf: url) }.value
                await apply(.replace(data), to: pending)
            } catch {
                problem = ArtworkProblem(title: "Couldn’t Use That Picture", message: error.localizedDescription)
            }
        }

        private func apply(_ artwork: AudioArtworkChange, to pending: ArtworkRequest) async {
            let result = await coordinator.setArtwork(artwork, for: pending.files, named: pending.title)
            problem = ArtworkProblem(result: result)
        }
    }

    private struct ArtworkProblem {
        let title: String
        let message: String

        init(title: String, message: String) {
            self.title = title
            self.message = message
        }

        init?(result: ArtworkUpdateResult) {
            guard !result.failures.isEmpty || result.skippedCount > 0 else { return nil }
            title = result.failures.isEmpty ? "Some Files Weren’t Changed" : "Some Artwork Couldn’t Be Changed"
            var parts: [String] = []
            if result.updatedCount > 0 {
                parts.append(Self.files(result.updatedCount) + " updated.")
            }
            if result.skippedCount > 0 {
                parts.append(Self.files(result.skippedCount) + " still in iCloud kept their old artwork. "
                    + "Download them, then try again.")
            }
            parts.append(contentsOf: result.failures.map { "\($0.fileName): \($0.message)" })
            message = parts.joined(separator: "\n")
        }

        private static func files(_ count: Int) -> String {
            count == 1 ? "1 file" : "\(count) files"
        }
    }

    public extension View {
        /// Runs the Choose/Remove Artwork requests raised by `ArtworkMenuItems`.
        func artworkRequests(_ request: Binding<ArtworkRequest?>, coordinator: LibraryCoordinator) -> some View {
            modifier(ArtworkRequestModifier(request: request, coordinator: coordinator))
        }
    }
#endif
