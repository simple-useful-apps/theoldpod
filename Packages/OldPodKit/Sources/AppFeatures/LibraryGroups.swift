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
    /// The album-level artist tag was empty (displayed as "Unknown Artist").
    public let isUnknownArtist: Bool
    /// The album tag was empty (displayed as "Unknown Album").
    public let isUnknownAlbum: Bool
    /// The first non-nil `artworkID` found among the album's tracks, in the
    /// order they were passed to `LibraryGroups.albums(from:)`.
    public let artworkID: String?
    /// Sorted disc, then track number, then title. `Track`s themselves never
    /// cross actor boundaries, so only their identifiers are kept here.
    public let trackIDs: [PersistentIdentifier]
}

/// A derived "artist" — one per unique `albumArtist ?? artist`, plus one per
/// track artist credited on someone else's album (e.g. a compilation),
/// matched case-insensitively. Never stored; always recomputed from `Track`s.
public struct ArtistGroup: Identifiable, Equatable, Sendable {
    /// The case/whitespace-normalized artist name — unique per group, so it
    /// doubles as a stable identifier.
    public var id: String
    /// Display-ready: the artist's name, or "Unknown Artist" if empty.
    public let name: String
    /// This artist's albums, sorted by year then title ("Unknown Album"
    /// last). A compilation they appear on holds only their tracks.
    public let albums: [AlbumGroup]
    /// Tracks in this group, counting compilation appearances.
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
    /// then `year`, then `title` (both case-insensitively), with "Unknown
    /// Album" albums after all titled ones and "Unknown Artist" after named
    /// artists.
    @MainActor
    public static func albums(from tracks: [Track]) -> [AlbumGroup] {
        var accumulators: [String: AlbumAccumulator] = [:]
        var order: [String] = []

        for track in tracks where !track.isAudiobook {
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

    /// One group per distinct `albumArtist ?? artist` (the album-level
    /// artist, e.g. "Various Artists" for a compilation), plus one per
    /// distinct *track* artist that differs from its track's album artist —
    /// so Björk's song on a compilation also lists under Björk, holding just
    /// her tracks (her albums then show the compilation with only her songs).
    /// A track can therefore appear in two groups. Names match
    /// case-insensitively (with leading/trailing whitespace ignored); the
    /// display name prefers album-artist casing. Sorted by
    /// `SortKeys.articleStripped(name)` — e.g. "The Fixtures" sorts under F —
    /// with "Unknown Artist" last.
    @MainActor
    public static func artists(from tracks: [Track]) -> [ArtistGroup] {
        var accumulators: [String: ArtistAccumulator] = [:]
        var order: [String] = []

        func add(_ track: Track, key: String, nameRaw: String, isAlbumArtist: Bool) {
            if accumulators[key] == nil {
                order.append(key)
                accumulators[key] = ArtistAccumulator()
            }
            accumulators[key]?.tracks.append(track)
            if isAlbumArtist {
                if accumulators[key]?.albumArtistName == nil { accumulators[key]?.albumArtistName = nameRaw }
            } else if accumulators[key]?.trackArtistName == nil {
                accumulators[key]?.trackArtistName = nameRaw
            }
        }

        for track in tracks where !track.isAudiobook {
            let primaryRaw = track.albumArtist ?? track.artist
            let primaryKey = normalizedKey(primaryRaw)
            add(track, key: primaryKey, nameRaw: primaryRaw, isAlbumArtist: true)

            let trackArtistKey = normalizedKey(track.artist)
            if !trackArtistKey.isEmpty, trackArtistKey != primaryKey {
                add(track, key: trackArtistKey, nameRaw: track.artist, isAlbumArtist: false)
            }
        }

        let groups = order.compactMap { key -> ArtistGroup? in
            guard let accumulator = accumulators[key] else { return nil }
            let nameRaw = accumulator.albumArtistName ?? accumulator.trackArtistName ?? ""
            return ArtistGroup(
                id: key,
                name: displayValue(nameRaw, fallback: "Unknown Artist"),
                albums: albums(from: accumulator.tracks).sorted(by: artistAlbumOrdering),
                trackCount: accumulator.tracks.count
            )
        }
        return groups.sorted { lhs, rhs in
            // The empty key is "Unknown Artist": it files after every name.
            if lhs.id.isEmpty != rhs.id.isEmpty { return rhs.id.isEmpty }
            return articleStrippedKey(lhs.name) < articleStrippedKey(rhs.name)
        }
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
        /// First-seen casing as an album artist, preferred for display.
        var albumArtistName: String?
        /// First-seen casing as a track artist, used when the name never
        /// appears as an album artist.
        var trackArtistName: String?
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
            isUnknownArtist: normalizedKey(accumulator.artistRaw).isEmpty,
            isUnknownAlbum: normalizedKey(accumulator.albumRaw).isEmpty,
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

    /// "Unknown Album" albums file after every titled album, and within
    /// each of those runs "Unknown Artist" files after every named artist.
    private static func albumOrdering(_ lhs: AlbumGroup, _ rhs: AlbumGroup) -> Bool {
        if lhs.isUnknownAlbum != rhs.isUnknownAlbum { return rhs.isUnknownAlbum }
        if lhs.isUnknownArtist != rhs.isUnknownArtist { return rhs.isUnknownArtist }

        let lhsArtist = articleStrippedKey(lhs.artistName)
        let rhsArtist = articleStrippedKey(rhs.artistName)
        if lhsArtist != rhsArtist { return lhsArtist < rhsArtist }

        let lhsYear = lhs.year ?? Int.max
        let rhsYear = rhs.year ?? Int.max
        if lhsYear != rhsYear { return lhsYear < rhsYear }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    /// One artist's albums: by year then title, ignoring the album artist
    /// (their compilation appearances sit among their own records), with
    /// "Unknown Album" last.
    private static func artistAlbumOrdering(_ lhs: AlbumGroup, _ rhs: AlbumGroup) -> Bool {
        if lhs.isUnknownAlbum != rhs.isUnknownAlbum { return rhs.isUnknownAlbum }

        let lhsYear = lhs.year ?? Int.max
        let rhsYear = rhs.year ?? Int.max
        if lhsYear != rhsYear { return lhsYear < rhsYear }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    /// Case/whitespace-normalized grouping key.
    private static func normalizedKey(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The key used to order names, ignoring a leading "The ", case, and
    /// diacritics — so "Émile" files under E, not after Z.
    private static func articleStrippedKey(_ s: String) -> String {
        SortKeys.articleStripped(s).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The first-seen, display-ready value: trimmed raw text, or `fallback`
    /// if that's empty.
    private static func displayValue(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
