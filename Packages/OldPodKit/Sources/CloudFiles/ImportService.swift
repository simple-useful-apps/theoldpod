import Foundation
import UniformTypeIdentifiers

public struct ImportProgress: Sendable, Equatable {
    public let description: String
    public let completed: Int
    public let total: Int

    public init(description: String, completed: Int, total: Int) {
        self.description = description
        self.completed = completed
        self.total = total
    }
}

public struct ImportIssue: Sendable, Equatable {
    public let filename: String
    public let message: String

    public init(filename: String, message: String) {
        self.filename = filename
        self.message = message
    }
}

/// The outcome of an `ImportService.importFiles(at:)` call.
public struct ImportResult: Sendable, Equatable {
    /// Relative paths created (or already present) under the library root.
    public let imported: [String]
    public let failures: [ImportIssue]
    public let warnings: [ImportIssue]

    public init(imported: [String], failures: [ImportIssue] = [], warnings: [ImportIssue] = []) {
        self.imported = imported
        self.failures = failures
        self.warnings = warnings
    }

    /// Source filenames rejected as unsupported or that failed to copy.
    public var skipped: [String] {
        failures.map(\.filename)
    }

    public var report: String? {
        let issues = failures + warnings
        guard !issues.isEmpty else { return nil }
        return issues.map { "\($0.filename): \($0.message)" }.joined(separator: "\n")
    }
}

/// Copies user-picked files into the library folder. Purely a file-system
/// operation: it never touches SwiftData. The folder watcher discovers the
/// copied files and the indexer turns them into `Track`s.
public struct ImportService: Sendable {
    public static var supportedContentTypes: [UTType] {
        AudioFileSupport.supportedContentTypes
    }

    private let libraryRoot: URL
    private var fileManager: FileManager {
        .default
    }

    public init(libraryRoot: URL) {
        self.libraryRoot = libraryRoot
    }

    /// Explicit book import keeps untagged chapters out of Unknown Album.
    /// Never merge a new book into another book with the same supplied title.
    public func importAudiobook(
        at urls: [URL],
        title: String,
        onProgress: (@MainActor @Sendable (ImportProgress) -> Void)? = nil
    ) async -> ImportResult {
        let cleaned = title.filter { $0 != "/" && $0 != ":" && !$0.isNewline }
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let name = cleaned.isEmpty ? "Untitled Book" : cleaned
        let books = libraryRoot.appendingPathComponent("Audiobooks", isDirectory: true)
        var folder = books.appendingPathComponent(name, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: folder.path) {
            folder = books.appendingPathComponent("\(name) \(suffix)", isDirectory: true)
            suffix += 1
        }
        let result = await ImportService(libraryRoot: folder).importFiles(at: urls, onProgress: onProgress)
        return ImportResult(
            imported: result.imported.map { "Audiobooks/\(folder.lastPathComponent)/\($0)" },
            failures: result.failures,
            warnings: result.warnings
        )
    }

    /// Copies the given files into the library root, flat (no subfolders
    /// invented). Supported extensions are matched case-insensitively.
    public func importFiles(
        at urls: [URL],
        onProgress: (@MainActor @Sendable (ImportProgress) -> Void)? = nil
    ) async -> ImportResult {
        if !fileManager.fileExists(atPath: libraryRoot.path) {
            try? fileManager.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        }

        var imported: [String] = []
        var failures: [ImportIssue] = []
        var warnings: [ImportIssue] = []
        var candidates: [URL] = []
        var scopedURLs: [URL] = []

        for url in urls {
            let filename = url.lastPathComponent
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            if didStartAccessing { scopedURLs.append(url) }

            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true else {
                failures.append(ImportIssue(filename: filename, message: "The file could not be read."))
                continue
            }
            if values.isDirectory == true {
                // Take the snapshot before copying, so dropping a folder
                // that contains the library cannot recursively import itself.
                guard let enumerator = fileManager.enumerator(
                    at: url, includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else {
                    failures.append(ImportIssue(filename: filename, message: "The folder could not be read."))
                    continue
                }
                let children = enumerator.compactMap { $0 as? URL }.filter { child in
                    guard AudioFileSupport.supportsImporting(child),
                          let values = try? child.resourceValues(forKeys: keys)
                    else { return false }
                    return values.isRegularFile == true && values.isSymbolicLink != true
                }.sorted { $0.path < $1.path }
                if children.isEmpty {
                    failures.append(ImportIssue(filename: filename, message: "No supported audio files were found."))
                } else {
                    candidates.append(contentsOf: children)
                }
            } else if values.isRegularFile == true, AudioFileSupport.supportsImporting(url) {
                candidates.append(url)
            } else {
                failures.append(ImportIssue(filename: filename, message: "This audio format is not supported."))
            }
        }

        defer {
            for url in scopedURLs {
                url.stopAccessingSecurityScopedResource()
            }
        }

        for (index, candidate) in candidates.enumerated() {
            if Task.isCancelled { break }
            let completed = index + 1
            #if os(macOS)
                if candidate.pathExtension.lowercased() == "wma" {
                    await onProgress?(ImportProgress(
                        description: "Converting \(candidate.lastPathComponent)",
                        completed: completed,
                        total: candidates.count
                    ))
                    do {
                        let conversion = try await WMAConverter().convert(candidate)
                        defer { conversion.removeTemporaryFiles() }
                        if Task.isCancelled { break }
                        let outputName = (candidate.deletingPathExtension().lastPathComponent as NSString)
                            .appendingPathExtension("m4a") ?? "Converted Audio.m4a"
                        if let relativePath = copyIntoLibrary(from: conversion.outputURL, filename: outputName) {
                            imported.append(relativePath)
                            warnings.append(contentsOf: conversion.warnings.map {
                                ImportIssue(filename: candidate.lastPathComponent, message: $0)
                            })
                        } else {
                            if Task.isCancelled { break }
                            failures.append(ImportIssue(filename: candidate.lastPathComponent, message: "The converted file could not be added to the library."))
                        }
                    } catch {
                        if error is CancellationError || Task.isCancelled { break }
                        failures.append(ImportIssue(filename: candidate.lastPathComponent, message: WMAConverter.userMessage(for: error)))
                    }
                    continue
                }
            #endif

            await onProgress?(ImportProgress(
                description: "Copying \(candidate.lastPathComponent)",
                completed: completed,
                total: candidates.count
            ))
            if let relativePath = copyIntoLibrary(from: candidate, filename: candidate.lastPathComponent) {
                imported.append(relativePath)
            } else {
                if Task.isCancelled { break }
                failures.append(ImportIssue(filename: candidate.lastPathComponent, message: "The file could not be copied."))
            }
        }

        return ImportResult(imported: imported, failures: failures, warnings: warnings)
    }

    /// Copies `source` into the library root under `filename`, resolving name
    /// collisions. Returns the relative path written (or the path of an
    /// identical file already there), or `nil` on failure.
    private func copyIntoLibrary(from source: URL, filename: String) -> String? {
        guard let sourceSize = fileSize(at: source) else { return nil }

        var candidate = filename
        var attempt = 1
        while true {
            let destination = libraryRoot.appendingPathComponent(candidate)
            if let existingSize = fileSize(at: destination) {
                // Same size alone isn't proof of identical content, so also
                // compare contents before treating this as a no-op:
                // a same-name, same-size, *different*-content file should
                // still get copied in under a suffixed name, not silently
                // dropped.
                if existingSize == sourceSize, filesAreIdentical(source, destination) {
                    // Identical file already present: treat as already imported.
                    return candidate
                }
                attempt += 1
                candidate = numberedFilename(filename, attempt: attempt)
                continue
            }

            do {
                let staging = libraryRoot.appendingPathComponent(".theoldpod-import-\(UUID().uuidString)")
                defer { try? fileManager.removeItem(at: staging) }
                try fileManager.copyItem(at: source, to: staging)
                guard !Task.isCancelled else { return nil }
                try fileManager.moveItem(at: staging, to: destination)
                return candidate
            } catch {
                return nil
            }
        }
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize
        else { return nil }
        return Int64(size)
    }

    /// Foundation compares contents without loading both files into Data or
    /// introducing a cryptographic dependency for ordinary duplicate checks.
    private func filesAreIdentical(_ lhs: URL, _ rhs: URL) -> Bool {
        fileManager.contentsEqual(atPath: lhs.path, andPath: rhs.path)
    }

    private func numberedFilename(_ filename: String, attempt: Int) -> String {
        let name = filename as NSString
        let stem = name.deletingPathExtension
        let ext = name.pathExtension
        return "\(stem) \(attempt).\(ext)"
    }
}
