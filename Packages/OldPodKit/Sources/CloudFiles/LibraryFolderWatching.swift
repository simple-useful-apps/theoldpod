/// Watches a library folder for audio files appearing, changing, or disappearing.
/// Two implementations exist: LocalFolderWatcher (DispatchSource over a local
/// directory) and UbiquityLibraryWatcher (NSMetadataQuery over the iCloud
/// container); the indexer consumes either through this one protocol.
public protocol LibraryFolderWatching: Sendable {
    /// First emission is the full current snapshot as upserts (empty array if
    /// folder empty). Subsequent emissions are diffs.
    func changes() -> AsyncStream<[LibraryChange]>
    func stop()
    func refresh() async throws
}
