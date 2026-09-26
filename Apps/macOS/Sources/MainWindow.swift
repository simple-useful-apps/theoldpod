import AppFeatures
import AppKit
import CloudFiles
import DesignSystem
import Domain
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The Mac window's root: a sidebar (Songs/Artists/Albums, plus user
/// playlists) and a detail pane, with the persistent player bar pinned to the
/// very top of the whole window — spanning sidebar and detail alike, the way
/// iTunes' transport bar always sat above everything else. Also owns music
/// import: a toolbar button and window-wide drag-and-drop, both funneled
/// through `ImportService`.
struct MacRootView: View {
    private let coordinator: LibraryCoordinator

    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]

    @State private var selection: SidebarItem? = .songs
    @State private var playlistSearch = ""

    @State private var rename: PlaylistRename?
    @State private var playlistPendingDelete: Playlist?
    @State private var isImporterPresented = false

    init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }

    var body: some View {
        // The bar is STACKED above the split view, not applied as a
        // safeAreaInset — AppKit-backed containers (the HSplitViews in the
        // Artists/Albums details) don't propagate SwiftUI safe-area insets,
        // so inset content slid underneath the bar (first album row halfway
        // hidden). Stacking makes underlap structurally impossible.
        VStack(spacing: 0) {
            PlayerBarView(player: coordinator.player, artworkDirectory: coordinator.artworkDirectory)

            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }
        }
        // Window minimum: toolbar + full-height player bar + a useful table.
        // Below this, the fixed-height bar + split-view minimums exceed the
        // window and the VStack spills up under the toolbar (clipped LCD).
        .frame(minWidth: 760, minHeight: 520)
        .toolbar {
            ToolbarItem(placement: .automatic) { LibraryStatusButton(coordinator: coordinator) }
            ToolbarItem(placement: .automatic) {
                if coordinator.importer.isImporting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        ImportProgressLabel(coordinator.importer)
                    }
                }
            }
            ToolbarItem(placement: .automatic) {
                if selection != .books {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Add Music", systemImage: "plus")
                    }
                    .help("Import music files into the library")
                }
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: ImportService.supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                coordinator.importer.importFiles(at: urls)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            coordinator.importer.importFiles(at: urls)
        }
        .importReportAlert(coordinator.importer)
        .task {
            coordinator.start()
            SpacebarPlayPause.install(player: coordinator.player)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            coordinator.player.saveProgress()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            coordinator.player.saveProgress()
        }
    }

    private var sidebar: some View {
        let filteredPlaylists = playlists.filter { playlistSearch.isEmpty || $0.name.localizedStandardContains(playlistSearch) }
        return List(selection: $selection) {
            Section("Library") {
                Label("Songs", systemImage: "music.note").tag(SidebarItem.songs)
                Label("Artists", systemImage: "music.mic").tag(SidebarItem.artists)
                Label("Albums", systemImage: "square.stack").tag(SidebarItem.albums)
                Label("Books", systemImage: "book.closed").tag(SidebarItem.books)
            }
            Section {
                TextField("Search Playlists", text: $playlistSearch)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search Playlists")
                ForEach(filteredPlaylists) { playlist in
                    Label(playlist.name, systemImage: "music.note.list")
                        .tag(SidebarItem.playlist(playlist.persistentModelID))
                        .contextMenu {
                            Button("Rename\u{2026}") { rename = PlaylistRename(playlist) }
                            Divider()
                            Button("Delete", role: .destructive) { playlistPendingDelete = playlist }
                        }
                }
                if !playlistSearch.isEmpty, filteredPlaylists.isEmpty {
                    Text("No matching playlists").foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("Playlists")
                    Spacer()
                    Button {
                        createPlaylist()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("New Playlist")
                    .help("New Playlist")
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        .playlistRenameAlert($rename, coordinator: coordinator)
        .playlistDeleteConfirmation(for: $playlistPendingDelete, coordinator: coordinator) { deleted in
            if selection == .playlist(deleted.persistentModelID) {
                selection = .songs
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .songs, nil:
            SongsTableView(coordinator: coordinator)
                .navigationTitle("Songs")
        case .artists:
            ArtistsDetailView(coordinator: coordinator)
                .navigationTitle("Artists")
        case .albums:
            AlbumsDetailView(coordinator: coordinator)
                .navigationTitle("Albums")
        case .books:
            NavigationStack { BooksView(coordinator: coordinator) }
        case let .playlist(id):
            if let playlist = playlists.first(where: { $0.persistentModelID == id }) {
                PlaylistDetailView(playlist: playlist, coordinator: coordinator)
                    .navigationTitle(playlist.name)
            } else {
                ContentUnavailableView(
                    "Playlist Deleted",
                    systemImage: "music.note.list",
                    description: Text("Select another playlist from the sidebar.")
                )
            }
        }
    }

    // MARK: - Playlist sidebar actions

    private func createPlaylist() {
        let playlist = coordinator.playlists.create(name: "New Playlist")
        selection = .playlist(playlist.persistentModelID)
        rename = PlaylistRename(playlist)
    }
}

private enum SidebarItem: Hashable {
    case songs, artists, albums, books
    case playlist(PersistentIdentifier)
}

/// Artists list (left) | songs table filtered to the selected artist, or all
/// songs when nothing is selected (right).
private struct ArtistsDetailView: View {
    let coordinator: LibraryCoordinator

    @Query private var tracks: [Track]
    @State private var selectedArtistID: String?
    @State private var searchText = ""

    private static func matches(_ artist: ArtistGroup, _ query: String) -> Bool {
        artist.name.localizedStandardContains(query)
    }

    var body: some View {
        let artists = LibraryGroups.artists(from: tracks)
        HSplitView {
            GroupPickerPane(
                items: artists,
                noun: "Artists",
                emptySystemImage: "music.mic",
                emptyDescription: "Drop music files into\n\(coordinator.libraryRoot.path)",
                listIdentifier: "artistsList",
                searchText: $searchText,
                selectedID: $selectedArtistID,
                matches: Self.matches
            ) { artist in
                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name)
                    Text(LibraryText.songCount(artist.trackCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 300)

            // An artist's songs read in album order, like their discography,
            // rather than A–Z by title.
            SongsTableView(
                coordinator: coordinator,
                filter: GroupPickerPane<ArtistGroup, EmptyView>.trackFilter(
                    items: artists,
                    selectedID: selectedArtistID,
                    searchText: searchText,
                    matches: Self.matches,
                    trackIDs: { $0.albums.flatMap(\.trackIDs) }
                ),
                initialSortOrder: SongsTableView.albumOrder
            )
            .frame(minWidth: 320)
        }
    }
}

/// Albums list (left) | songs table filtered to the selected album, sorted
/// disc/track by default (right).
private struct AlbumsDetailView: View {
    let coordinator: LibraryCoordinator

    @Query private var tracks: [Track]
    @State private var selectedAlbumID: String?
    @State private var searchText = ""

    private static func matches(_ album: AlbumGroup, _ query: String) -> Bool {
        album.title.localizedStandardContains(query) || album.artistName.localizedStandardContains(query)
    }

    var body: some View {
        let albums = LibraryGroups.albums(from: tracks)
        HSplitView {
            GroupPickerPane(
                items: albums,
                noun: "Albums",
                emptySystemImage: "square.stack",
                emptyDescription: "Drop music files into\n\(coordinator.libraryRoot.path)",
                listIdentifier: "albumsList",
                searchText: $searchText,
                selectedID: $selectedAlbumID,
                matches: Self.matches
            ) { album in
                HStack(spacing: 8) {
                    ArtworkImage(artworkID: album.artworkID, directory: coordinator.artworkDirectory, pointSize: 56)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(album.title)
                            .lineLimit(1)
                        Text(album.artistName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            // Sidebar + this pane + the table's minimum must fit the default
            // 1000pt window; at 240…340 + 400 the split view overflowed and
            // clipped the sidebar's leading edge and the Time column.
            .frame(minWidth: 220, idealWidth: 240, maxWidth: 300)

            SongsTableView(
                coordinator: coordinator,
                filter: GroupPickerPane<AlbumGroup, EmptyView>.trackFilter(
                    items: albums,
                    selectedID: selectedAlbumID,
                    searchText: searchText,
                    matches: Self.matches,
                    trackIDs: \.trackIDs
                ),
                initialSortOrder: SongsTableView.albumOrder
            )
            .frame(minWidth: 320)
        }
    }
}
