import CloudFiles
import DesignSystem
import Domain
import PlaybackEngine
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The Songs tab: every `Track` in the library, sorted by title, with live
/// case/diacritic-insensitive search over title/artist/album. Tapping a row
/// plays the whole visible list starting at that row; long-press offers
/// Play Next / Add to Queue / Add to Playlist; the toolbar button imports
/// supported audio files into the library folder.
struct SongsListView: View {
    // `.localizedStandard` (Finder-style: case/diacritic-insensitive), not the
    // store's default binary order, which filed every lowercase title after Z.
    @Query(sort: [SortDescriptor(\Track.title, comparator: .localizedStandard)]) private var tracks: [Track]
    @State private var searchText = ""

    @State private var isPresentingFileImporter = false
    @State private var trackPendingPlaylistAdd: Track?
    @State private var deletionRequest: LibraryDeletionRequest?

    private let coordinator: LibraryCoordinator

    init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }

    /// `tracks` narrowed to those matching `searchText` in title, artist, or
    /// album — case and diacritic insensitive. Empty query means "no filter."
    private var filteredTracks: [Track] {
        let music = tracks.filter { !$0.isAudiobook }
        guard !searchText.isEmpty else { return music }
        let needle = Self.fold(searchText) // fold once, not per track
        return music.filter { Self.matches($0, needle: needle) }
    }

    var body: some View {
        let filteredTracks = filteredTracks
        Group {
            if !tracks.contains(where: { !$0.isAudiobook }) {
                ContentUnavailableView(
                    "No Music Yet",
                    systemImage: "music.note",
                    description: Text("Drop music files into\n\(coordinator.libraryRoot.path)")
                )
            } else if filteredTracks.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(Array(filteredTracks.enumerated()), id: \.element.persistentModelID) { index, track in
                        SongRow(
                            track: track,
                            isCurrent: coordinator.player.current?.relativePath == track.relativePath,
                            artworkDirectory: coordinator.artworkDirectory
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            coordinator.play(filteredTracks, startingAt: index)
                        }
                        .contextMenu {
                            TrackContextMenuContent(
                                track: track,
                                coordinator: coordinator,
                                onDelete: { deletionRequest = .songs([SongDeletionTarget(track: track)]) },
                                onAddToPlaylist: { trackPendingPlaylistAdd = track }
                            )
                        }
                        .deleteSwipeAction("Delete Song") { deletionRequest = .songs([SongDeletionTarget(track: track)]) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search Songs")
        .refreshable { await coordinator.refreshLibrary() }
        .toolbar {
            ToolbarItem(placement: .automatic) { LibraryStatusButton(coordinator: coordinator) }
            ToolbarItem(placement: .primaryAction) {
                if coordinator.importer.isImporting {
                    ProgressView()
                } else {
                    Button {
                        isPresentingFileImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Music")
                }
            }
        }
        .fileImporter(
            isPresented: $isPresentingFileImporter,
            allowedContentTypes: ImportService.supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                coordinator.importer.importFiles(at: urls)
            }
        }
        .importReportAlert(coordinator.importer)
        .addToPlaylistSheet(for: $trackPendingPlaylistAdd, coordinator: coordinator)
        .libraryDeletionConfirmation(request: $deletionRequest, coordinator: coordinator)
    }

    private static func matches(_ track: Track, needle: String) -> Bool {
        fold(track.title).contains(needle)
            || fold(track.artist).contains(needle)
            || fold(track.album).contains(needle)
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

private struct SongRow: View {
    let track: Track
    let isCurrent: Bool
    let artworkDirectory: URL?

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(artworkID: track.artworkID, directory: artworkDirectory)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .lineLimit(2)
                Text(track.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
            } else if !track.isDownloaded {
                Image(systemName: "icloud.and.arrow.down")
                    .foregroundStyle(.secondary)
            } else {
                DurationText(track.duration)
            }
        }
    }
}
