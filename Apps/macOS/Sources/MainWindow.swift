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

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]

    @State private var selection: SidebarItem? = .songs
    @State private var playlistSearch = ""

    @State private var playlistPendingRename: Playlist?
    @State private var renameText = ""
    @State private var playlistPendingDelete: Playlist?

    @State private var isImporterPresented = false
    @State private var isImporting = false
    @State private var importProgress: ImportProgress?
    @State private var importReport: String?

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
                if isImporting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        if let progress = importProgress {
                            Text("\(progress.description) (\(progress.completed) of \(progress.total))")
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
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
                startImport(of: urls)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            startImport(of: urls)
        }
        .alert(
            "Import Finished with Issues",
            isPresented: Binding(
                get: { importReport != nil },
                set: { if !$0 { importReport = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importReport ?? "")
        }
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
        List(selection: $selection) {
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
                ForEach(playlists.filter { playlistSearch.isEmpty || $0.name.localizedStandardContains(playlistSearch) }) { playlist in
                    Label(playlist.name, systemImage: "music.note.list")
                        .tag(SidebarItem.playlist(playlist.persistentModelID))
                        .contextMenu {
                            Button("Rename\u{2026}") { beginRename(playlist) }
                            Divider()
                            Button("Delete", role: .destructive) { playlistPendingDelete = playlist }
                        }
                }
                if !playlistSearch.isEmpty, !playlists.contains(where: { $0.name.localizedStandardContains(playlistSearch) }) {
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
        .alert(
            "Rename Playlist",
            isPresented: Binding(
                get: { playlistPendingRename != nil },
                set: { if !$0 { playlistPendingRename = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let playlist = playlistPendingRename {
                    PlaylistOps.rename(playlist, to: renameText, in: modelContext)
                }
                playlistPendingRename = nil
            }
            Button("Cancel", role: .cancel) {
                playlistPendingRename = nil
            }
        }
        .confirmationDialog(
            "Delete Playlist?",
            isPresented: Binding(
                get: { playlistPendingDelete != nil },
                set: { if !$0 { playlistPendingDelete = nil } }
            ),
            presenting: playlistPendingDelete
        ) { playlist in
            Button("Delete \u{201C}\(playlist.name)\u{201D}", role: .destructive) {
                deletePlaylist(playlist)
            }
            Button("Cancel", role: .cancel) {
                playlistPendingDelete = nil
            }
        } message: { _ in
            Text("This can\u{2019}t be undone.")
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
        let playlist = PlaylistOps.create(name: "New Playlist", in: modelContext)
        selection = .playlist(playlist.persistentModelID)
        beginRename(playlist)
    }

    private func beginRename(_ playlist: Playlist) {
        renameText = playlist.name
        playlistPendingRename = playlist
    }

    private func deletePlaylist(_ playlist: Playlist) {
        if selection == .playlist(playlist.persistentModelID) {
            selection = .songs
        }
        PlaylistOps.delete(playlist, in: modelContext)
        playlistPendingDelete = nil
    }

    // MARK: - Import

    private func startImport(of urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        Task {
            let result = await ImportService(libraryRoot: coordinator.libraryRoot).importFiles(at: urls) { progress in
                importProgress = progress
            }
            if !result.imported.isEmpty {
                _ = await coordinator.refreshLibrary()
            }
            isImporting = false
            importProgress = nil
            importReport = result.report
        }
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

    var body: some View {
        // Grouped once per body evaluation — reading a computed property from
        // the empty-check, the List, AND the filter would regroup the whole
        // library three times per render.
        let artists = LibraryGroups.artists(from: tracks)
        HSplitView {
            VStack {
                TextField("Search Artists", text: $searchText).textFieldStyle(.roundedBorder).padding([.horizontal, .top], 8)
                    .onChange(of: searchText) { _, _ in selectedArtistID = nil }
                if artists.isEmpty {
                    ContentUnavailableView(
                        "No Artists Yet",
                        systemImage: "music.mic",
                        description: Text("Drop music files into\n\(coordinator.libraryRoot.path)")
                    )
                } else {
                    VStack {
                        List(selection: $selectedArtistID) {
                            ForEach(artists.filter { searchText.isEmpty || $0.name.localizedStandardContains(searchText) }) { artist in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(artist.name)
                                    Text(LibraryText.songCount(artist.trackCount))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .tag(artist.id)
                            }
                        }
                        // UI tests: an artist name (e.g. "The Fixtures") also
                        // appears verbatim in the Artist column of the
                        // SongsTableView right beside this list, so a bare label
                        // lookup for the row is ambiguous — this identifier lets
                        // tests scope the query to just this list.
                        .accessibilityIdentifier("artistsList")
                        .overlay {
                            if !searchText.isEmpty, !artists.contains(where: { $0.name.localizedStandardContains(searchText) }) {
                                Text("No matching artists").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 300)

            // An artist's songs read in album order, like their discography,
            // rather than A–Z by title.
            SongsTableView(
                coordinator: coordinator,
                filter: filter(artists: artists),
                initialSortOrder: [
                    KeyPathComparator(\.album, order: .forward),
                    KeyPathComparator(\.discNumber, order: .forward),
                    KeyPathComparator(\.trackNumber, order: .forward),
                ]
            )
            .frame(minWidth: 320)
        }
    }

    /// nil selection = all tracks; otherwise every track belonging to any of
    /// the selected artist's albums.
    private func filter(artists: [ArtistGroup]) -> (Track) -> Bool {
        guard let selectedArtistID, let group = artists.first(where: { $0.id == selectedArtistID }) else {
            if !searchText.isEmpty {
                let ids = Set(artists.filter { $0.name.localizedStandardContains(searchText) }.flatMap(\.albums).flatMap(\.trackIDs))
                return { ids.contains($0.persistentModelID) }
            }
            return { _ in true }
        }
        let ids = Set(group.albums.flatMap(\.trackIDs))
        return { ids.contains($0.persistentModelID) }
    }
}

/// Albums list (left) | songs table filtered to the selected album, sorted
/// disc/track by default (right).
private struct AlbumsDetailView: View {
    let coordinator: LibraryCoordinator

    @Query private var tracks: [Track]
    @State private var selectedAlbumID: String?
    @State private var searchText = ""

    var body: some View {
        // Grouped once per body evaluation (see ArtistsDetailView).
        let albums = LibraryGroups.albums(from: tracks)
        HSplitView {
            VStack {
                TextField("Search Albums", text: $searchText).textFieldStyle(.roundedBorder).padding([.horizontal, .top], 8)
                    .onChange(of: searchText) { _, _ in selectedAlbumID = nil }
                if albums.isEmpty {
                    ContentUnavailableView(
                        "No Albums Yet",
                        systemImage: "square.stack",
                        description: Text("Drop music files into\n\(coordinator.libraryRoot.path)")
                    )
                } else {
                    VStack {
                        List(selection: $selectedAlbumID) {
                            ForEach(albums.filter { searchText.isEmpty || $0.title.localizedStandardContains(searchText) || $0.artistName.localizedStandardContains(searchText) }) { album in
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
                                .tag(album.id)
                            }
                        }
                        // UI tests: an album title (e.g. "Covered") also appears
                        // verbatim in the Album column of the SongsTableView
                        // right beside this list — see the matching comment on
                        // `artistsList` above.
                        .accessibilityIdentifier("albumsList")
                        .overlay {
                            if !searchText.isEmpty, !albums.contains(where: { $0.title.localizedStandardContains(searchText) || $0.artistName.localizedStandardContains(searchText) }) {
                                Text("No matching albums").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            // Sidebar + this pane + the table's minimum must fit the default
            // 1000pt window; at 240…340 + 400 the split view overflowed and
            // clipped the sidebar's leading edge and the Time column.
            .frame(minWidth: 220, idealWidth: 240, maxWidth: 300)

            SongsTableView(
                coordinator: coordinator,
                filter: filter(albums: albums),
                initialSortOrder: [
                    KeyPathComparator(\.discNumber, order: .forward),
                    KeyPathComparator(\.trackNumber, order: .forward),
                ]
            )
            .frame(minWidth: 320)
        }
    }

    /// nil selection = all tracks; otherwise just the selected album's tracks.
    private func filter(albums: [AlbumGroup]) -> (Track) -> Bool {
        guard let selectedAlbumID, let group = albums.first(where: { $0.id == selectedAlbumID }) else {
            if !searchText.isEmpty {
                let ids = Set(albums.filter { $0.title.localizedStandardContains(searchText) || $0.artistName.localizedStandardContains(searchText) }.flatMap(\.trackIDs))
                return { ids.contains($0.persistentModelID) }
            }
            return { _ in true }
        }
        let ids = Set(group.trackIDs)
        return { ids.contains($0.persistentModelID) }
    }
}
