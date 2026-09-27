import Foundation

public struct LibraryDeletionFailure: Sendable, Equatable {
    public let target: String
    public let message: String

    public init(target: String, message: String) {
        self.target = target
        self.message = message
    }
}

public struct LibraryDeletionResult: Sendable, Equatable {
    public let successfulTargets: [String]
    public let alreadyMissingTargets: [String]
    public let failures: [LibraryDeletionFailure]
    public let postDeletionWarning: String?

    public init(
        successfulTargets: [String] = [],
        alreadyMissingTargets: [String] = [],
        failures: [LibraryDeletionFailure] = [],
        postDeletionWarning: String? = nil
    ) {
        self.successfulTargets = successfulTargets
        self.alreadyMissingTargets = alreadyMissingTargets
        self.failures = failures
        self.postDeletionWarning = postDeletionWarning
    }

    public var succeededTargets: [String] {
        successfulTargets + alreadyMissingTargets
    }

    public var isCompleteSuccess: Bool {
        failures.isEmpty
    }
}

/// Moves files owned by the library to the platform Trash. Every target is
/// resolved through `LibraryRoot` both before and inside file coordination.
public struct LibraryDeletionService: Sendable {
    private let root: LibraryRoot

    public init(libraryRoot: URL) {
        root = LibraryRoot(url: libraryRoot)
    }

    public func deleteSongs(relativePaths: [String]) async -> LibraryDeletionResult {
        let root = root
        let paths = Self.deduplicated(relativePaths)
        return await Task.detached {
            var successful: [String] = []
            var missing: [String] = []
            var failures: [LibraryDeletionFailure] = []

            for path in paths {
                do {
                    guard try Self.songExists(at: path, in: root) else {
                        missing.append(path)
                        continue
                    }
                    try Self.moveToTrash(path, in: root, stillExists: Self.songExists)
                    successful.append(path)
                } catch {
                    failures.append(.init(target: path, message: Self.userMessage(for: error)))
                }
            }
            return LibraryDeletionResult(
                successfulTargets: successful,
                alreadyMissingTargets: missing,
                failures: failures
            )
        }.value
    }

    public func deleteBook(named name: String) async -> LibraryDeletionResult {
        let root = root
        return await Task.detached {
            do {
                let path = try Self.bookPath(named: name)
                guard try Self.bookExists(at: path, in: root) else {
                    return LibraryDeletionResult(alreadyMissingTargets: [path])
                }
                try Self.moveToTrash(path, in: root, stillExists: Self.bookExists)
                return LibraryDeletionResult(successfulTargets: [path])
            } catch {
                return LibraryDeletionResult(failures: [
                    .init(target: name, message: Self.userMessage(for: error)),
                ])
            }
        }.value
    }

    private enum ValidationError: LocalizedError {
        case unsupportedAudio
        case wrongItemType

        var errorDescription: String? {
            switch self {
            case .unsupportedAudio: "The item is not a supported music file."
            case .wrongItemType: "The library item has an unexpected type."
            }
        }
    }

    private static func deduplicated(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.filter { seen.insert($0).inserted }
    }

    private static func bookPath(named name: String) throws -> String {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains(":"), !name.contains("\0")
        else { throw LibraryRoot.Error.unsafePath }
        return "Audiobooks/\(name)"
    }

    /// `true` for an existing supported audio file, `false` when nothing is
    /// at `path`; anything else at that path is an error.
    private static func songExists(at path: String, in root: LibraryRoot) throws -> Bool {
        guard AudioFileSupport.supports(URL(fileURLWithPath: path)) else { throw ValidationError.unsupportedAudio }
        guard let values = try root.inspect(path) else { return false }
        guard values.isRegularFile == true else { throw ValidationError.wrongItemType }
        return true
    }

    private static func bookExists(at path: String, in root: LibraryRoot) throws -> Bool {
        guard let values = try root.inspect(path) else { return false }
        guard values.isDirectory == true else { throw ValidationError.wrongItemType }
        return true
    }

    private static func moveToTrash(
        _ path: String,
        in root: LibraryRoot,
        stillExists: @escaping (String, LibraryRoot) throws -> Bool
    ) throws {
        let target = try root.resolve(path)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?
        coordinator.coordinate(writingItemAt: target, options: .forDeleting, error: &coordinationError) { coordinatedURL in
            do {
                guard coordinatedURL.standardizedFileURL == target else { throw LibraryRoot.Error.unsafePath }
                guard try stillExists(path, root) else { throw CocoaError(.fileNoSuchFile) }
                try FileManager.default.trashItem(at: coordinatedURL, resultingItemURL: nil)
            } catch {
                operationError = error
            }
        }
        if let operationError { throw operationError }
        if let coordinationError { throw coordinationError }
    }

    private static func userMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "The item couldn’t be moved to Trash."
    }
}
