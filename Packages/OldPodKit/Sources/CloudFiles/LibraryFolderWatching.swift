/// Watches a library folder for MP3 files appearing, changing, or disappearing.
/// Abstracted so M5 can swap in an NSMetadataQuery-backed iCloud implementation
/// without touching callers.
public protocol LibraryFolderWatching: Sendable {
    /// First emission is the full current snapshot as upserts (empty array if
    /// folder empty). Subsequent emissions are diffs.
    func changes() -> AsyncStream<[LibraryChange]>
    func stop()
}
