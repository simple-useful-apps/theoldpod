import AppFeatures
import DesignSystem
import Domain
import SwiftData
import SwiftUI

/// The Mac window's root: a sidebar (Songs/Artists/Albums, plus a Playlists
/// placeholder) and a detail pane, with the persistent player bar pinned to
/// the very top of the whole window — spanning sidebar and detail alike, the
/// way iTunes' transport bar always sat above everything else.
struct MacRootView: View {
    private let coordinator: LibraryCoordinator

    @State private var selection: SidebarItem? = .songs

    init(coordinator: LibraryCoordinator) {
        self.coordinator = coordinator
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PlayerBarView(player: coordinator.player, artworkDirectory: coordinator.artworkDirectory)
        }
        .task {
            coordinator.start()
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("Songs", systemImage: "music.note").tag(SidebarItem.songs)
                Label("Artists", systemImage: "music.mic").tag(SidebarItem.artists)
                Label("Albums", systemImage: "square.stack").tag(SidebarItem.albums)
            }
            Section("Playlists") {
                Text("Playlists arrive in the next update")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
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
        }
    }
}

private enum SidebarItem: Hashable {
    case songs, artists, albums
}

/// Artists list (left) | songs table filtered to the selected artist, or all
/// songs when nothing is selected (right).
private struct ArtistsDetailView: View {
    let coordinator: LibraryCoordinator

    @Query private var tracks: [Track]
    @State private var selectedArtistID: String?

    private var artists: [ArtistGroup] {
        LibraryGroups.artists(from: tracks)
    }

    var body: some View {
        HSplitView {
            Group {
                if artists.isEmpty {
                    ContentUnavailableView(
                        "No Artists Yet",
                        systemImage: "music.mic",
                        description: Text("Drop MP3s into\n\(coordinator.libraryRoot.path)")
                    )
                } else {
                    List(selection: $selectedArtistID) {
                        ForEach(artists) { artist in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artist.name)
                                Text("\(artist.trackCount) song\(artist.trackCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(artist.id)
                        }
                    }
                }
            }
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 320)

            SongsTableView(coordinator: coordinator, filter: filter)
                .frame(minWidth: 400)
        }
    }

    /// nil selection = all tracks; otherwise every track belonging to any of
    /// the selected artist's albums.
    private var filter: (Track) -> Bool {
        guard let selectedArtistID, let group = artists.first(where: { $0.id == selectedArtistID }) else {
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

    private var albums: [AlbumGroup] {
        LibraryGroups.albums(from: tracks)
    }

    var body: some View {
        HSplitView {
            Group {
                if albums.isEmpty {
                    ContentUnavailableView(
                        "No Albums Yet",
                        systemImage: "square.stack",
                        description: Text("Drop MP3s into\n\(coordinator.libraryRoot.path)")
                    )
                } else {
                    List(selection: $selectedAlbumID) {
                        ForEach(albums) { album in
                            HStack(spacing: 8) {
                                ArtworkImage(artworkID: album.artworkID, directory: coordinator.artworkDirectory)
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
                }
            }
            .frame(minWidth: 240, idealWidth: 260, maxWidth: 340)

            SongsTableView(
                coordinator: coordinator,
                filter: filter,
                initialSortOrder: [
                    KeyPathComparator(\.discNumber, order: .forward),
                    KeyPathComparator(\.trackNumber, order: .forward),
                ]
            )
            .frame(minWidth: 400)
        }
    }

    /// nil selection = all tracks; otherwise just the selected album's tracks.
    private var filter: (Track) -> Bool {
        guard let selectedAlbumID, let group = albums.first(where: { $0.id == selectedAlbumID }) else {
            return { _ in true }
        }
        let ids = Set(group.trackIDs)
        return { ids.contains($0.persistentModelID) }
    }
}
