import Darwin
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
/// validated both before and inside file coordination so a symlink swap or a
/// malformed relative path cannot escape the configured library root.
public struct LibraryDeletionService: Sendable {
    private let libraryRoot: URL
    private let rootAnchor: RootAnchor?

    public init(libraryRoot: URL) {
        self.libraryRoot = libraryRoot.standardizedFileURL
        rootAnchor = try? Self.captureRootAnchor(for: libraryRoot.standardizedFileURL)
    }

    public func deleteSongs(relativePaths: [String]) async -> LibraryDeletionResult {
        let root = libraryRoot
        let anchor = rootAnchor
        let paths = Self.deduplicated(relativePaths)
        return await Task.detached {
            var successful: [String] = []
            var missing: [String] = []
            var failures: [LibraryDeletionFailure] = []

            for path in paths {
                do {
                    let anchor = try Self.requireValidRoot(anchor, at: root)
                    let target = try Self.validatedSongURL(relativePath: path, root: root, anchor: anchor)
                    guard try Self.inspectTarget(target, root: root, anchor: anchor, expected: .song) == .exists else {
                        missing.append(path)
                        continue
                    }
                    try Self.moveToTrash(target, relativeTarget: path, root: root, anchor: anchor, expected: .song)
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
        let root = libraryRoot
        let anchor = rootAnchor
        return await Task.detached {
            do {
                let anchor = try Self.requireValidRoot(anchor, at: root)
                let relativePath = try Self.validatedBookRelativePath(name: name)
                let target = try Self.validatedBookURL(name: name, root: root, anchor: anchor)
                guard try Self.inspectTarget(target, root: root, anchor: anchor, expected: .book) == .exists else {
                    return LibraryDeletionResult(alreadyMissingTargets: [relativePath])
                }
                try Self.moveToTrash(target, relativeTarget: relativePath, root: root, anchor: anchor, expected: .book)
                return LibraryDeletionResult(successfulTargets: [relativePath])
            } catch {
                return LibraryDeletionResult(failures: [
                    .init(target: name, message: Self.userMessage(for: error)),
                ])
            }
        }.value
    }

    private enum ExpectedTarget {
        case song, book
    }

    private enum TargetPresence {
        case exists, missing
    }

    private struct RootIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    private struct RootAnchor {
        let canonicalURL: URL
        let identity: RootIdentity
    }

    private enum ValidationError: LocalizedError {
        case unsafePath
        case unsupportedAudio
        case wrongItemType
        case symbolicLink
        case unavailableRoot

        var errorDescription: String? {
            switch self {
            case .unsafePath: "The item is outside the library or has an unsafe path."
            case .unsupportedAudio: "The item is not a supported music file."
            case .wrongItemType: "The library item has an unexpected type."
            case .symbolicLink: "Symbolic links can’t be deleted from the app."
            case .unavailableRoot: "The library folder changed or is no longer available. Refresh the library and try again."
            }
        }
    }

    private static func deduplicated(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.filter { seen.insert($0).inserted }
    }

    private static func validatedSongURL(relativePath: String, root: URL, anchor: RootAnchor) throws -> URL {
        try validateRoot(anchor, at: root)
        let components = try validatedComponents(relativePath)
        guard let last = components.last,
              ["mp3", "m4a"].contains((last as NSString).pathExtension.lowercased())
        else {
            throw ValidationError.unsupportedAudio
        }
        let target = components.reduce(root) { $0.appendingPathComponent($1) }.standardizedFileURL
        try validateContainment(of: target, root: root)
        return target
    }

    private static func validatedBookRelativePath(name: String) throws -> String {
        guard !name.isEmpty,
              name != ".", name != "..",
              !name.contains("/"), !name.contains(":"), !name.contains("\0")
        else {
            throw ValidationError.unsafePath
        }
        return "Audiobooks/\(name)"
    }

    private static func validatedBookURL(name: String, root: URL, anchor: RootAnchor) throws -> URL {
        try validateRoot(anchor, at: root)
        _ = try validatedBookRelativePath(name: name)
        let target = root
            .appendingPathComponent("Audiobooks", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
            .standardizedFileURL
        try validateContainment(of: target, root: root)
        guard target.deletingLastPathComponent().lastPathComponent == "Audiobooks" else {
            throw ValidationError.unsafePath
        }
        return target
    }

    private static func validatedComponents(_ relativePath: String) throws -> [String] {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            throw ValidationError.unsafePath
        }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ValidationError.unsafePath
        }
        return components
    }

    private static func validateContainment(of target: URL, root: URL) throws {
        let rootPath = root.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        guard targetPath.hasPrefix(rootPath + "/"), targetPath != rootPath else {
            throw ValidationError.unsafePath
        }
    }

    private static func inspectTarget(
        _ target: URL,
        root: URL,
        anchor: RootAnchor,
        expected: ExpectedTarget
    ) throws -> TargetPresence {
        try validateRoot(anchor, at: root)
        let rootComponents = root.standardizedFileURL.pathComponents
        let targetComponents = target.standardizedFileURL.pathComponents
        guard targetComponents.starts(with: rootComponents) else { throw ValidationError.unsafePath }

        var candidate = root.standardizedFileURL
        for component in targetComponents.dropFirst(rootComponents.count) {
            candidate.appendPathComponent(component)
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) != nil {
                throw ValidationError.symbolicLink
            }
            let values: URLResourceValues
            do {
                values = try candidate.resourceValues(forKeys: [
                    .isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey,
                ])
            } catch {
                if isNoSuchFile(error) { return .missing }
                throw error
            }
            if values.isSymbolicLink == true { throw ValidationError.symbolicLink }
            if candidate != target {
                guard values.isDirectory == true else { throw ValidationError.wrongItemType }
            } else {
                switch expected {
                case .song:
                    guard values.isRegularFile == true else { throw ValidationError.wrongItemType }
                    guard ["mp3", "m4a"].contains(target.pathExtension.lowercased()) else {
                        throw ValidationError.unsupportedAudio
                    }
                case .book:
                    guard values.isDirectory == true,
                          target.deletingLastPathComponent().lastPathComponent == "Audiobooks"
                    else {
                        throw ValidationError.wrongItemType
                    }
                }
            }
        }
        return .exists
    }

    private static func moveToTrash(
        _ target: URL,
        relativeTarget: String,
        root: URL,
        anchor: RootAnchor,
        expected: ExpectedTarget
    ) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?
        coordinator.coordinate(writingItemAt: target, options: .forDeleting, error: &coordinationError) { coordinatedURL in
            do {
                try validateRoot(anchor, at: root)
                let expectedURL = try expectedURL(for: relativeTarget, root: root, anchor: anchor, expected: expected)
                guard coordinatedURL.standardizedFileURL == expectedURL.standardizedFileURL else {
                    throw ValidationError.unsafePath
                }
                guard try inspectTarget(coordinatedURL, root: root, anchor: anchor, expected: expected) == .exists else {
                    throw CocoaError(.fileNoSuchFile)
                }
                try FileManager.default.trashItem(at: coordinatedURL, resultingItemURL: nil)
            } catch {
                operationError = error
            }
        }
        if let operationError { throw operationError }
        if let coordinationError { throw coordinationError }
    }

    private static func expectedURL(
        for relativeTarget: String,
        root: URL,
        anchor: RootAnchor,
        expected: ExpectedTarget
    ) throws -> URL {
        switch expected {
        case .song:
            return try validatedSongURL(relativePath: relativeTarget, root: root, anchor: anchor)
        case .book:
            guard relativeTarget.hasPrefix("Audiobooks/") else { throw ValidationError.unsafePath }
            return try validatedBookURL(
                name: String(relativeTarget.dropFirst("Audiobooks/".count)),
                root: root,
                anchor: anchor
            )
        }
    }

    private static func captureRootAnchor(for root: URL) throws -> RootAnchor {
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL
        return try RootAnchor(canonicalURL: canonical, identity: rootIdentity(of: canonical))
    }

    private static func requireValidRoot(_ anchor: RootAnchor?, at root: URL) throws -> RootAnchor {
        guard let anchor else { throw ValidationError.unavailableRoot }
        try validateRoot(anchor, at: root)
        return anchor
    }

    private static func validateRoot(_ anchor: RootAnchor, at root: URL) throws {
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL
        guard canonical == anchor.canonicalURL,
              try rootIdentity(of: canonical) == anchor.identity
        else {
            throw ValidationError.unavailableRoot
        }
    }

    private static func rootIdentity(of url: URL) throws -> RootIdentity {
        var information = stat()
        guard lstat(url.path, &information) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard information.st_mode & S_IFMT == S_IFDIR else {
            throw ValidationError.unavailableRoot
        }
        return RootIdentity(device: UInt64(information.st_dev), inode: UInt64(information.st_ino))
    }

    private static func isNoSuchFile(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileNoSuchFile.rawValue)
            || (error.domain == NSPOSIXErrorDomain && error.code == ENOENT)
    }

    private static func userMessage(for error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription {
            return description
        }
        return "The item couldn’t be moved to Trash."
    }
}
