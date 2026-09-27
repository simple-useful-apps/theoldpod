import CloudFiles
import Domain
import SwiftUI

public struct SongDeletionTarget: Sendable, Hashable {
    public let relativePath: String
    public let title: String

    @MainActor
    public init(track: Track) {
        relativePath = track.relativePath
        title = track.title
    }
}

public enum LibraryDeletionRequest: Identifiable, Sendable, Hashable {
    case songs([SongDeletionTarget])
    case book(name: String)

    public var id: String {
        switch self {
        case let .songs(targets): "songs:" + targets.map(\.relativePath).joined(separator: "|")
        case let .book(name): "book:" + name
        }
    }

    fileprivate var title: String {
        switch self {
        case let .songs(targets):
            targets.count == 1 ? "Delete \(targets[0].title)?" : "Delete \(targets.count) Songs?"
        case let .book(name):
            "Delete \(name)?"
        }
    }

    fileprivate var buttonTitle: String {
        switch self {
        case let .songs(targets):
            targets.count == 1 ? "Delete Song" : "Delete \(targets.count) Songs"
        case .book:
            "Delete Book"
        }
    }

    fileprivate func explanation(isCloudLibrary: Bool) -> String {
        let base: String = switch self {
        case let .songs(targets):
            targets.count == 1
                ? "The selected library file will be moved to Trash."
                : "The selected library files will be moved to Trash."
        case .book:
            "The book folder and all of its contents will be moved to Trash."
        }
        let location = isCloudLibrary
            ? "This deletion will sync through iCloud to your other devices."
            : "This library is only on this device."
        return "\(base) \(location) Originals imported from elsewhere are unchanged."
    }
}

public struct LibraryDeletionCompletion: Sendable {
    public let request: LibraryDeletionRequest
    public let result: LibraryDeletionResult

    public var succeededSongPaths: Set<String> {
        guard case .songs = request else { return [] }
        return Set(result.succeededTargets)
    }

    public var bookWasDeleted: Bool {
        guard case .book = request else { return false }
        return result.isCompleteSuccess
    }
}

private struct LibraryDeletionConfirmationModifier: ViewModifier {
    @Binding var request: LibraryDeletionRequest?
    let coordinator: LibraryCoordinator
    let onCompletion: (LibraryDeletionCompletion) -> Void
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                request?.title ?? "Delete Library Item?",
                isPresented: Binding(
                    get: { request != nil },
                    set: { if !$0 { request = nil } }
                ),
                titleVisibility: .visible,
                presenting: request
            ) { pending in
                Button(pending.buttonTitle, role: .destructive) {
                    request = nil
                    Task { await perform(pending) }
                }
                Button("Cancel", role: .cancel) { request = nil }
            } message: { pending in
                Text(pending.explanation(isCloudLibrary: coordinator.isCloudLibrary))
            }
            .alert(
                resultAlertTitle,
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    @MainActor
    private func perform(_ pending: LibraryDeletionRequest) async {
        let result: LibraryDeletionResult = switch pending {
        case let .songs(targets):
            await coordinator.deleteSongs(relativePaths: targets.map(\.relativePath))
        case let .book(name):
            await coordinator.deleteBook(named: name)
        }
        onCompletion(.init(request: pending, result: result))
        if !result.failures.isEmpty || result.postDeletionWarning != nil {
            errorMessage = [
                result.failures.isEmpty ? nil : failureMessage(for: result),
                result.postDeletionWarning,
            ].compactMap(\.self).joined(separator: "\n\n")
        }
    }

    private var resultAlertTitle: String {
        errorMessage?.hasPrefix("The selected files were moved to Trash") == true
            ? "Deleted, But Refresh Was Incomplete"
            : "Some Items Couldn’t Be Deleted"
    }

    private func failureMessage(for result: LibraryDeletionResult) -> String {
        var parts: [String] = []
        if !result.successfulTargets.isEmpty {
            parts.append("\(result.successfulTargets.count) item\(result.successfulTargets.count == 1 ? " was" : "s were") moved to Trash.")
        }
        if !result.alreadyMissingTargets.isEmpty {
            parts.append("\(result.alreadyMissingTargets.count) item\(result.alreadyMissingTargets.count == 1 ? " was" : "s were") already missing.")
        }
        parts.append(contentsOf: result.failures.map { "\($0.target): \($0.message)" })
        return parts.joined(separator: "\n")
    }
}

public extension View {
    func libraryDeletionConfirmation(
        request: Binding<LibraryDeletionRequest?>,
        coordinator: LibraryCoordinator,
        onCompletion: @escaping (LibraryDeletionCompletion) -> Void = { _ in }
    ) -> some View {
        modifier(LibraryDeletionConfirmationModifier(
            request: request,
            coordinator: coordinator,
            onCompletion: onCompletion
        ))
    }
}
