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
    _ = DomainModule.self
    _ = LibraryStoreModule.self
    _ = MetadataImportModule.self
    _ = CloudFilesModule.self
    _ = PlaybackEngineModule.self
    _ = NowPlayingModule.self
    _ = OldPodTypography.timeReadout()
}
