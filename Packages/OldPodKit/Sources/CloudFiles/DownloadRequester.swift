import Foundation

/// Kicks off downloading an iCloud placeholder file's real bytes.
public enum DownloadRequester {
    /// Best-effort `startDownloadingUbiquitousItem`. A no-op for files that
    /// aren't ubiquitous items (e.g. anything under the local library root),
    /// which simply fails and returns `false`.
    @discardableResult
    public static func requestDownload(of url: URL) -> Bool {
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            return true
        } catch {
            return false
        }
    }
}
