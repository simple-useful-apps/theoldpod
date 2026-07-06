import AppFeatures
import DesignSystem
import Domain
import Foundation
import PlaybackEngine
import SwiftData
import SwiftUI

/// A plain value-type row for `Table`, projected from a SwiftData `Track`.
/// Tables want `Identifiable` value types, not `@Model` reference types, so
/// only the `PersistentIdentifier` crosses back to `Track` (via
/// `LibraryGroups.tracks(for:in:)`) when an action needs the real model.
struct SongRow: Identifiable, Equatable {
    let id: PersistentIdentifier
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    /// Untagged disc/track numbers default the same way `LibraryGroups`
    /// orders albums (disc 1, track sorts last) so the "sorted disc/track by
    /// default" album view reads sensibly even for partially-tagged albums.
    let discNumber: Int
    let trackNumber: Int
    let artworkID: String?
    let relativePath: String

    @MainActor
    init(track: Track) {
        id = track.persistentModelID
        title = track.title
        artist = track.artist.isEmpty ? "Unknown Artist" : track.artist
        album = track.album.isEmpty ? "Unknown Album" : track.album
        duration = track.duration
        discNumber = track.discNumber ?? 1
        trackNumber = track.trackNumber ?? Int.max
        artworkID = track.artworkID
        relativePath = track.relativePath
    }
}

/// The Mac songs table: every `Track` in the library (optionally narrowed by
/// `filter`, e.g. to one artist or album), sortable by column, searchable,
/// and playable via double-click or context menu. Reused by the Songs,
/// Artists, and Albums sidebar destinations in `MacRootView`.
struct SongsTableView: View {
    @Query(sort: [SortDescriptor(\Track.title)]) private var tracks: [Track]
    @Environment(\.modelContext) private var modelContext

    private let coordinator: LibraryCoordinator
    private let filter: (Track) -> Bool

    @State private var sortOrder: [KeyPathComparator<SongRow>]
    @State private var searchText = ""
    @State private var selection: Set<PersistentIdentifier> = []

    init(
        coordinator: LibraryCoordinator,
        filter: @escaping (Track) -> Bool = { _ in true },
        initialSortOrder: [KeyPathComparator<SongRow>] = [KeyPathComparator(\.title, order: .forward)]
    ) {
        self.coordinator = coordinator
        self.filter = filter
        _sortOrder = State(initialValue: initialSortOrder)
    }

    var body: some View {
        Group {
            if tracks.isEmpty {
                ContentUnavailableView(
                    "No Music Yet",
                    systemImage: "music.note",
                    description: Text("Drop MP3s into\n\(coordinator.libraryRoot.path)")
                )
            } else {
                let rows = visibleRows
                if rows.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    table(for: rows)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search")
    }

    private func table(for rows: [SongRow]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.title) { row in
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .opacity(isCurrent(row) ? 1 : 0)
                        .frame(width: 12)
                    Text(row.title)
                        .lineLimit(1)
                }
            }
            TableColumn("Artist", value: \.artist)
            TableColumn("Album", value: \.album)
            TableColumn("Time", value: \.duration) { row in
                Text(DurationText.format(row.duration))
                    .font(OldPodTypography.timeReadout())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 46, ideal: 60, max: 90)
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            Button("Play") { play(ids) }
            Button("Play Next") { playNext(ids) }
            Button("Add to Queue") { addToQueue(ids) }
        } primaryAction: { ids in
            playFromVisibleOrder(clicked: ids)
        }
    }

    /// `tracks` (already narrowed by `filter`) turned into rows, then further
    /// narrowed by the search field, then sorted — this is "the current
    /// visible row order" that double-click and the context menu play from.
    private var visibleRows: [SongRow] {
        var rows = tracks.filter(filter).map(SongRow.init(track:))
        if !searchText.isEmpty {
            rows = rows.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                    $0.artist.localizedCaseInsensitiveContains(searchText) ||
                    $0.album.localizedCaseInsensitiveContains(searchText)
            }
        }
        rows.sort(using: sortOrder)
        return rows
    }

    private func isCurrent(_ row: SongRow) -> Bool {
        coordinator.player.current?.relativePath == row.relativePath
    }

    /// Resolves `ids` back into `Track`s, preserving the current visible row
    /// order (not `Set` iteration order).
    private func orderedTracks(matching ids: Set<PersistentIdentifier>) -> [Track] {
        let orderedIDs = visibleRows.map(\.id).filter(ids.contains)
        return LibraryGroups.tracks(for: orderedIDs, in: modelContext)
    }

    /// Double-click: play the whole visible list, starting at the clicked row.
    private func playFromVisibleOrder(clicked ids: Set<PersistentIdentifier>) {
        let orderedIDs = visibleRows.map(\.id)
        guard let clickedID = ids.first, let index = orderedIDs.firstIndex(of: clickedID) else { return }
        let allTracks = LibraryGroups.tracks(for: orderedIDs, in: modelContext)
        coordinator.player.play(coordinator.playableTracks(from: allTracks), startingAt: index)
    }

    /// Context menu "Play": play just the selected row(s), in visible order.
    private func play(_ ids: Set<PersistentIdentifier>) {
        let tracks = orderedTracks(matching: ids)
        guard !tracks.isEmpty else { return }
        coordinator.player.play(coordinator.playableTracks(from: tracks), startingAt: 0)
    }

    private func playNext(_ ids: Set<PersistentIdentifier>) {
        let playables = coordinator.playableTracks(from: orderedTracks(matching: ids))
        for playable in playables.reversed() {
            coordinator.player.playNext(playable)
        }
    }

    private func addToQueue(_ ids: Set<PersistentIdentifier>) {
        let playables = coordinator.playableTracks(from: orderedTracks(matching: ids))
        for playable in playables {
            coordinator.player.append(playable)
        }
    }
}
