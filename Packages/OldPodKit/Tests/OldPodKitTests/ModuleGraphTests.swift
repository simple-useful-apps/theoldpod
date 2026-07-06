import AppFeatures
import CloudFiles
import DesignSystem
import Domain
import LibraryStore
import MetadataImport
import NowPlaying
import PlaybackEngine
import Testing

@Test func packageModuleGraphBuildsAndLinks() {
    // Touch a symbol in every module so the whole dependency graph compiles and links.
    _ = LibrarySchema.models
    _ = LocalFolderWatcher.self
    _ = TrackMetadata.self
    _ = LibraryContainerFactory.self
    _ = PlaybackEngineModule.self
    _ = NowPlayingModule.self
    _ = OldPodTypography.timeReadout()
    _ = LibraryCoordinator.self
}
