import AppFeatures
import AppKit
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
struct SongTableRow: Identifiable, Equatable {
    let id: PersistentIdentifier
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    /// Untagged disc/track numbers default the same way `LibraryGroups`
    /// orders albums (disc 1, track sorts last) so the "sorted disc/track by
    /// default" album view reads sensibly even for partially-tagged albums.
    /// Case-folded `(album, albumArtist ?? artist)` — the same pairing
    /// `LibraryGroups` uses — so an unfiltered Albums/Artists table keeps each
    /// album's tracks together, even when two artists share an album title.
    let albumSortKey: String
    let discNumber: Int
    let trackNumber: Int
    /// The "#" column: disc, then track (untagged tracks last within a disc).
    let discTrack: DiscTrack
    /// The tagged track number for display; `nil` shows a blank "#" cell.
    let trackTag: Int?
    let artworkID: String?
    let relativePath: String
    let isDownloaded: Bool

    @MainActor
    init(track: Track) {
        id = track.persistentModelID
        title = track.title
        artist = track.displayArtist
        album = track.displayAlbum
        duration = track.duration
        albumSortKey = [album, track.albumArtist ?? artist]
            .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
            .joined(separator: "\u{1F}")
        discNumber = track.discNumber ?? 1
        trackNumber = track.trackNumber ?? Int.max
        discTrack = DiscTrack(disc: discNumber, track: trackNumber)
        trackTag = track.trackNumber
        artworkID = track.artworkID
        relativePath = track.relativePath
        isDownloaded = track.isDownloaded
    }
}

/// Sort key for the "#" column: disc first, then track.
struct DiscTrack: Comparable {
    let disc: Int
    let track: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.disc, lhs.track) < (rhs.disc, rhs.track)
    }
}

/// Published by the focused song table so Play (menu, Space, player bar) can
/// start something when nothing is queued: the selected rows in visible
/// order, or the whole visible list when nothing is selected.
struct PlaySelectionActionKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}

extension FocusedValues {
    var playSelectionAction: PlaySelectionActionKey.Value? {
        get { self[PlaySelectionActionKey.self] }
        set { self[PlaySelectionActionKey.self] = newValue }
    }
}

/// The Mac songs table: every `Track` in the library (optionally narrowed by
/// `filter`, e.g. to one artist or album), sortable by column, searchable,
/// and playable via double-click or context menu. Reused by the Songs,
/// Artists, and Albums sidebar destinations in `MacRootView`.
struct SongsTableView: View {
    @Query(sort: [SortDescriptor(\Track.title)]) private var tracks: [Track]
    @Query(sort: [SortDescriptor(\Playlist.name, comparator: .localizedStandard)]) private var playlists: [Playlist]
    @Environment(\.modelContext) private var modelContext

    private let coordinator: LibraryCoordinator
    private let filter: (Track) -> Bool
    /// Only the Songs sidebar destination answers Go to Current Song.
    private let revealsCurrentSong: Bool
    @Environment(MacWindowActions.self) private var windowActions: MacWindowActions?

    @State private var sortOrder: [KeyPathComparator<SongTableRow>]
    @State private var searchText = ""
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var deletionRequest: LibraryDeletionRequest?
    @State private var pendingDeletionIDs: [String: PersistentIdentifier] = [:]
    @State private var metadataEditor: MetadataEditorPresentation?
    @State private var scrollTarget: PersistentIdentifier?

    /// Album, then disc, then track: with no album selected, disc/track alone
    /// would interleave every album's track 1s, then its 2s, and so on.
    static let albumOrder: [KeyPathComparator<SongTableRow>] = [
        KeyPathComparator(\.albumSortKey, order: .forward),
        KeyPathComparator(\.discNumber, order: .forward),
        KeyPathComparator(\.trackNumber, order: .forward),
    ]

    init(
        coordinator: LibraryCoordinator,
        filter: @escaping (Track) -> Bool = { _ in true },
        initialSortOrder: [KeyPathComparator<SongTableRow>] = [KeyPathComparator(\.title, order: .forward)],
        revealsCurrentSong: Bool = false
    ) {
        self.coordinator = coordinator
        self.revealsCurrentSong = revealsCurrentSong
        self.filter = { !$0.isAudiobook && filter($0) }
        _sortOrder = State(initialValue: initialSortOrder)
    }

    var body: some View {
        let rows = visibleRows
        Group {
            if !tracks.contains(where: filter) {
                ContentUnavailableView(
                    "No Music Yet",
                    systemImage: "music.note",
                    description: Text("Drop music files into\n\(coordinator.libraryRoot.path)")
                )
            } else if rows.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        table(for: rows)
                            .onChange(of: scrollTarget) { _, target in
                                guard let target else { return }
                                // After the search clear has re-rendered rows.
                                Task { @MainActor in
                                    proxy.scrollTo(target, anchor: .center)
                                    scrollTarget = nil
                                }
                            }
                    }
                    Divider()
                    Text(Self.statusLine(for: rows))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("songsStatusLine")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search")
        .onDeleteCommand {
            requestDeletion(for: selection)
        }
        .focusedSceneValue(\.getInfoAction, getInfoAction(rows: rows))
        .focusedSceneValue(\.playSelectionAction, playSelectionAction(rows: rows))
        .onChange(of: windowActions?.isRevealingCurrentSong ?? false, initial: true) { _, isRevealing in
            guard revealsCurrentSong, isRevealing else { return }
            windowActions?.isRevealingCurrentSong = false
            revealCurrentSong()
        }
        .sheet(item: $metadataEditor) { request in
            MetadataEditorView(request: request, coordinator: coordinator)
        }
        .libraryDeletionConfirmation(
            request: $deletionRequest,
            coordinator: coordinator
        ) { completion in
            let succeeded = completion.succeededSongPaths
            selection.subtract(Set(succeeded.compactMap { pendingDeletionIDs[$0] }))
            pendingDeletionIDs = [:]
        }
    }

    private func table(for rows: [SongTableRow]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("#", value: \.discTrack) { row in
                Text(row.trackTag.map(String.init) ?? "")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 24, ideal: 30, max: 44)
            TableColumn("Title", value: \.title) { row in
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        // Accent-on-accent vanished in a selected row.
                        .foregroundStyle(selection.contains(row.id) ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                        .opacity(isCurrent(row) ? 1 : 0)
                        .frame(width: 12)
                    Text(row.title)
                        .lineLimit(1)
                }
            }
            TableColumn("Artist", value: \.artist)
            TableColumn("Album", value: \.album)
            TableColumn("Time", value: \.duration) { row in
                if row.isDownloaded {
                    Text(DurationText.format(row.duration))
                        .font(OldPodTypography.timeReadout())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            // Wide enough for an hour-long "1:10:00" readout even when a narrow
            // Artists/Albums pane squeezes the table.
            .width(min: 64, ideal: 72, max: 96)
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            Button("Play") { play(ids) }
            Button("Play Next") { playNext(ids) }
            Button("Add to Queue") { addToQueue(ids) }
            Divider()
            Menu("Add to Playlist") {
                ForEach(playlists) { playlist in
                    Button(playlist.name) { addToPlaylist(playlist, ids: ids) }
                }
                if !playlists.isEmpty {
                    Divider()
                }
                Button("New Playlist\u{2026}") { addToNewPlaylist(ids) }
            }
            Divider()
            Button("Get Info") { openInfo(for: ids) }
                .disabled(editableTrack(for: ids) == nil)
            Button("Show in Finder") { showInFinder(ids) }
                .disabled(ids.isEmpty)
            Divider()
            Button("Delete", role: .destructive) { requestDeletion(for: ids) }
        } primaryAction: { ids in
            playFromVisibleOrder(clicked: ids)
        }
    }

    /// `tracks` (already narrowed by `filter`) turned into rows, then further
    /// narrowed by the search field, then sorted — this is "the current
    /// visible row order" that double-click and the context menu play from.
    private var visibleRows: [SongTableRow] {
        var rows = tracks.filter(filter).map(SongTableRow.init(track:))
        if !searchText.isEmpty {
            rows = rows.filter {
                $0.title.localizedStandardContains(searchText) ||
                    $0.artist.localizedStandardContains(searchText) ||
                    $0.album.localizedStandardContains(searchText)
            }
        }
        rows.sort(using: sortOrder)
        return rows
    }

    private func isCurrent(_ row: SongTableRow) -> Bool {
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
        coordinator.play(allTracks, startingAt: index)
    }

    /// Context menu "Play": play just the selected row(s), in visible order.
    private func play(_ ids: Set<PersistentIdentifier>) {
        let tracks = orderedTracks(matching: ids)
        guard !tracks.isEmpty else { return }
        coordinator.play(tracks, startingAt: 0)
    }

    private func playNext(_ ids: Set<PersistentIdentifier>) {
        coordinator.playNext(orderedTracks(matching: ids))
    }

    private func addToQueue(_ ids: Set<PersistentIdentifier>) {
        coordinator.enqueue(orderedTracks(matching: ids))
    }

    private func addToPlaylist(_ playlist: Playlist, ids: Set<PersistentIdentifier>) {
        for track in orderedTracks(matching: ids) {
            coordinator.playlists.add(track, to: playlist)
        }
    }

    private func addToNewPlaylist(_ ids: Set<PersistentIdentifier>) {
        let playlist = coordinator.playlists.create(name: "New Playlist")
        addToPlaylist(playlist, ids: ids)
    }

    /// "40 songs, 3.1 hours" (or "12 minutes", or "1.5 days") for the rows
    /// currently visible — the old iTunes status line.
    static func statusLine(for rows: [SongTableRow]) -> String {
        let total = rows.reduce(0) { $0 + max($1.duration, 0) }
        let duration: String
        if total < 3600 {
            let minutes = Int((total / 60).rounded())
            duration = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        } else if total < 86400 {
            duration = String(format: "%.1f hours", total / 3600)
        } else {
            duration = String(format: "%.1f days", total / 86400)
        }
        return "\(LibraryText.songCount(rows.count)), \(duration)"
    }

    /// Play with nothing queued: the selection in visible order, else the
    /// whole visible list from the top.
    private func playSelectionAction(rows: [SongTableRow]) -> (@MainActor () -> Void)? {
        guard !rows.isEmpty else { return nil }
        let selected = rows.map(\.id).filter(selection.contains)
        let ids = selected.isEmpty ? rows.map(\.id) : selected
        return {
            let tracks = LibraryGroups.tracks(for: ids, in: modelContext)
            guard !tracks.isEmpty else { return }
            coordinator.play(tracks, startingAt: 0)
        }
    }

    /// Go to Current Song: clear the search so the row is visible, then
    /// select it and scroll it into view.
    private func revealCurrentSong() {
        guard let path = coordinator.player.current?.relativePath,
              let track = tracks.first(where: { $0.relativePath == path && filter($0) })
        else { return }
        searchText = ""
        selection = [track.persistentModelID]
        scrollTarget = track.persistentModelID
    }

    private func showInFinder(_ ids: Set<PersistentIdentifier>) {
        let urls = orderedTracks(matching: ids).map { coordinator.libraryRoot.appendingPathComponent($0.relativePath) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func getInfoAction(rows: [SongTableRow]) -> (@MainActor () -> Void)? {
        guard selection.count == 1, let row = rows.first(where: { selection.contains($0.id) }), row.isDownloaded else { return nil }
        return { openInfo(for: selection) }
    }

    private func editableTrack(for ids: Set<PersistentIdentifier>) -> Track? {
        guard ids.count == 1, let track = orderedTracks(matching: ids).first, track.isDownloaded else { return nil }
        return track
    }

    private func openInfo(for ids: Set<PersistentIdentifier>) {
        guard let track = editableTrack(for: ids) else { return }
        metadataEditor = MetadataEditorPresentation(
            relativePath: track.relativePath,
            artworkID: track.artworkID,
            duration: track.duration
        )
    }

    private func requestDeletion(for ids: Set<PersistentIdentifier>) {
        let selectedTracks = orderedTracks(matching: ids)
        let targets = selectedTracks.map(SongDeletionTarget.init(track:))
        guard !targets.isEmpty else { return }
        pendingDeletionIDs = Dictionary(uniqueKeysWithValues: selectedTracks.map { ($0.relativePath, $0.persistentModelID) })
        deletionRequest = .songs(targets)
    }
}
