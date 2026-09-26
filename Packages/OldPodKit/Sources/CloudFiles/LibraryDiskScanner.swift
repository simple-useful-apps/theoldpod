import Foundation

struct LibraryDiskScan {
    let files: [String: LibraryFileStat]
    let directories: [URL]
}

/// Produces a complete, point-in-time view of the library folder away from
/// the caller's actor. A failed enumeration is never returned as a partial
/// snapshot because consumers use absence to drive destructive index deletes.
enum LibraryDiskScanner {
    static func scan(root: URL, cloudAware: Bool) async throws -> LibraryDiskScan {
        let task = Task.detached(priority: .utility) {
            try scanSynchronously(root: root, cloudAware: cloudAware)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func scanSynchronously(root: URL, cloudAware: Bool) throws -> LibraryDiskScan {
        try Task.checkCancellation()

        let fileManager = FileManager.default
        let errorBox = ScanErrorBox()
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isHiddenKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: cloudAware ? [] : [.skipsHiddenFiles],
            errorHandler: { _, error in
                errorBox.error = error
                return false
            }
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        var files: [String: LibraryFileStat] = [:]
        var directories = [root]
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: keys)

            if values.isDirectory == true {
                if values.isSymbolicLink == true || values.isHidden == true {
                    enumerator.skipDescendants()
                } else {
                    directories.append(url)
                }
                continue
            }
            guard values.isSymbolicLink != true else { continue }

            let isNamedPlaceholder = cloudAware
                && url.lastPathComponent.hasPrefix(".")
                && url.pathExtension.caseInsensitiveCompare("icloud") == .orderedSame
            let logicalURL: URL
            if isNamedPlaceholder {
                let name = String(url.deletingPathExtension().lastPathComponent.dropFirst())
                logicalURL = url.deletingLastPathComponent().appendingPathComponent(name)
            } else {
                guard values.isHidden != true else { continue }
                logicalURL = url
            }
            guard AudioFileSupport.supports(logicalURL),
                  let path = LibraryLocation.relativePath(of: logicalURL, under: root)
            else { continue }

            let isDownloaded = if isNamedPlaceholder {
                false
            } else if cloudAware, values.isUbiquitousItem == true {
                switch values.ubiquitousItemDownloadingStatus {
                case .notDownloaded?:
                    false
                default:
                    // A normal file URL with no explicit not-downloaded state
                    // has locally addressable bytes. Some File Provider roots
                    // omit the status even for fully materialized files.
                    true
                }
            } else {
                true
            }

            files[path] = LibraryFileStat(
                size: Int64(values.fileSize ?? 0),
                modified: values.contentModificationDate ?? Date(timeIntervalSince1970: 0),
                isDownloaded: isDownloaded
            )
        }

        if let error = errorBox.error { throw error }
        return LibraryDiskScan(files: files, directories: directories)
    }
}

private final class ScanErrorBox: @unchecked Sendable {
    var error: (any Error)?
}
