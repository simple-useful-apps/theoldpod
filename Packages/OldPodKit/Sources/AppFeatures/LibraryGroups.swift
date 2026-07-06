import Domain
import Foundation
import SwiftData

/// A derived "album" — one per unique `(albumArtist ?? artist, album)` pair,
/// matched case-insensitively so "Abbey Road" and "abbey road" merge into a
/// single group. Albums are never stored; they're recomputed from `Track`s
/// every time the library changes.
public struct AlbumGroup: Identifiable, Equatable, Sendable {
    /// The case/whitespace-normalized `(albumArtist, album)` pair. Stable
    /// across recomputation as long as the underlying tags don't change.
    public var id: String
    /// Display-ready: `album.isEmpty ? "Unknown Album" : album`.
    public let title: String
    /// Display-ready: `albumArtist ?? artist`, or "Unknown Artist" if empty.
    public let artistName: String
    /// The minimum non-nil `year` across the album's tracks.
    public let year: Int?
    /// The first non-nil `artworkID` found among the album's tracks, in the
    /// order they were passed to `LibraryGroups.albums(from:)`.
    public let artworkID: String?
    /// Sorted disc, then track number, then title. `Track`s themselves never
    /// cross actor boundaries, so only their identifiers are kept here.
    public let trackIDs: [PersistentIdentifier]
}

/// A derived "artist" — one per unique `albumArtist ?? artist`, matched
/// case-insensitively. Never stored; always recomputed from `Track`s.
public struct ArtistGroup: Identifiable, Equatable, Sendable {
    /// The case/whitespace-normalized artist name — unique per group, so it
    /// doubles as a stable identifier.
    public var id: String
    /// Display-ready: the artist's name, or "Unknown Artist" if empty.
    public let name: String
    /// This artist's albums, sorted by year then title.
    public let albums: [AlbumGroup]
    public let trackCount: Int
}

/// Pure, `@MainActor` derivations of Artists/Albums groupings from `Track`s.
/// Artists and Albums are never stored entities (per the project's data
/// model rule) — they're recomputed here whenever the UI needs them.
public enum LibraryGroups {
    /// Groups `tracks` by `(albumArtist ?? artist, album)`, matched
    /// case-insensitively (with leading/trailing whitespace ignored) so
    /// compilation albums where every track shares an explicit `albumArtist`
    /// collapse into a single `AlbumGroup` even though each track's own
    /// `artist` differs. Sorted by `SortKeys.articleStripped(artistName)`,
    /// then `year`, then `title` (both case-insensitively).
    @MainActor
    public static func albums(from tracks: [Track]) -> [AlbumGroup] {
        var accumulators: [String: AlbumAccumulator] = [:]
        var order: [String] = []

        for track in tracks {
            let artistRaw = track.albumArtist ?? track.artist
            let key = normalizedKey(artistRaw) + "\u{1F}" + normalizedKey(track.album)
            if accumulators[key] == nil {
                order.append(key)
                accumulators[key] = AlbumAccumulator(artistRaw: artistRaw, albumRaw: track.album)
            }
            accumulators[key]?.tracks.append(track)
        }

        let groups = order.compactMap { key in accumulators[key].map { makeAlbumGroup(id: key, accumulator: $0) } }
        return groups.sorted(by: albumOrdering)
    }

    /// Groups `tracks` by `albumArtist ?? artist`, matched case-insensitively
    /// (with leading/trailing whitespace ignored). Sorted by
    /// `SortKeys.articleStripped(name)` — e.g. "The Fixtures" sorts under F.
    @MainActor
    public static func artists(from tracks: [Track]) -> [ArtistGroup] {
        var accumulators: [String: ArtistAccumulator] = [:]
        var order: [String] = []

        for track in tracks {
            let nameRaw = track.albumArtist ?? track.artist
            let key = normalizedKey(nameRaw)
            if accumulators[key] == nil {
                order.append(key)
                accumulators[key] = ArtistAccumulator(nameRaw: nameRaw)
            }
            accumulators[key]?.tracks.append(track)
        }

        let groups = order.compactMap { key -> ArtistGroup? in
            guard let accumulator = accumulators[key] else { return nil }
            return ArtistGroup(
                id: key,
                name: displayValue(accumulator.nameRaw, fallback: "Unknown Artist"),
                // Every track here already shares the same artist key, so
                // reusing `albums(from:)` naturally yields "sorted by year
                // then title" for this artist's albums alone.
                albums: albums(from: accumulator.tracks),
                trackCount: accumulator.tracks.count
            )
        }
        return groups.sorted { articleStrippedKey($0.name) < articleStrippedKey($1.name) }
    }

    /// Resolves `ids` back into `Track`s, in the same order, for handing to
    /// `player.play(_:startingAt:)`. `Track` is a `@Model` and must stay on
    /// the main actor, which is why `AlbumGroup`/`ArtistGroup` only carry
    /// `PersistentIdentifier`s in the first place.
    ///
    /// Uses a `FetchDescriptor` rather than `context.model(for:)`: the latter
    /// happily hands back a faulted object for an ID whose backing row was
    /// since deleted (e.g. the track's file vanished and the library was
    /// reindexed), and touching that object's properties later crashes.
    /// Fetching only returns IDs that still exist, so a stale ID is simply
    /// dropped instead.
    @MainActor
    public static func tracks(for ids: [PersistentIdentifier], in context: ModelContext) -> [Track] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { ids.contains($0.persistentModelID) })
        let fetched = (try? context.fetch(descriptor)) ?? []
        let tracksByID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.persistentModelID, $0) })
        return ids.compactMap { tracksByID[$0] }
    }

    // MARK: - Grouping helpers

    private struct AlbumAccumulator {
        let artistRaw: String
        let albumRaw: String
        var tracks: [Track] = []
    }

    private struct ArtistAccumulator {
        let nameRaw: String
        var tracks: [Track] = []
    }

    @MainActor
    private static func makeAlbumGroup(id: String, accumulator: AlbumAccumulator) -> AlbumGroup {
        let sortedTracks = accumulator.tracks.sorted(by: trackOrdering)
        return AlbumGroup(
            id: id,
            title: displayValue(accumulator.albumRaw, fallback: "Unknown Album"),
            artistName: displayValue(accumulator.artistRaw, fallback: "Unknown Artist"),
            year: accumulator.tracks.compactMap(\.year).min(),
            artworkID: accumulator.tracks.lazy.compactMap(\.artworkID).first,
            trackIDs: sortedTracks.map(\.persistentModelID)
        )
    }

    /// Disc, then track number, then title — untagged disc/track numbers
    /// sort as if disc 1 / after every tagged track, respectively.
    private static func trackOrdering(_ lhs: Track, _ rhs: Track) -> Bool {
        let lhsDisc = lhs.discNumber ?? 1
        let rhsDisc = rhs.discNumber ?? 1
        if lhsDisc != rhsDisc { return lhsDisc < rhsDisc }

        let lhsTrackNumber = lhs.trackNumber ?? Int.max
        let rhsTrackNumber = rhs.trackNumber ?? Int.max
        if lhsTrackNumber != rhsTrackNumber { return lhsTrackNumber < rhsTrackNumber }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private static func albumOrdering(_ lhs: AlbumGroup, _ rhs: AlbumGroup) -> Bool {
        let lhsArtist = articleStrippedKey(lhs.artistName)
        let rhsArtist = articleStrippedKey(rhs.artistName)
        if lhsArtist != rhsArtist { return lhsArtist < rhsArtist }

        let lhsYear = lhs.year ?? Int.max
        let rhsYear = rhs.year ?? Int.max
        if lhsYear != rhsYear { return lhsYear < rhsYear }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    /// Case/whitespace-normalized grouping key.
    private static func normalizedKey(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The key used to order names, ignoring a leading "The " and case.
    private static func articleStrippedKey(_ s: String) -> String {
        SortKeys.articleStripped(s).lowercased()
    }

    /// The first-seen, display-ready value: trimmed raw text, or `fallback`
    /// if that's empty.
    private static func displayValue(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
