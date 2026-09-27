# A tour of the codebase

A reading order for learning how The Old Pod works. Total source is small (~5k lines); this path covers the load-bearing 80% in roughly an afternoon. Everything interesting lives in `Packages/OldPodKit/Sources/`; the two app targets in `Apps/` are deliberately thin shells.

## The one-paragraph architecture

MP3 files in a folder are the database. A **watcher** turns filesystem events into diffs, an **indexer** turns diffs into SwiftData `Track` rows, SwiftUI **views** query those rows, and taps hand value-type snapshots of tracks to a **player** that drives `AVQueuePlayer`. Nothing else. Every subsystem below is one leg of that sentence.

## Reading order

### 1. `Domain/` — the vocabulary (10 min)

`Track.swift`, `Playlist.swift`, `PlaylistEntry.swift`. Three SwiftData models, nothing clever. Two deliberate choices to notice: artists/albums are **never stored** (they're derived groupings — see step 4), and `PlaylistEntry` references tracks by *string path*, not a relationship, so playlists survive files coming and going — and are exported as plain `.m3u8` files (see step 4's `PlaylistFileSync`).

### 2. `CloudFiles/` — files become diffs (30 min)

Start with `LibraryChange.swift` (the diff vocabulary: upsert/remove of a `LibraryFile`) and `LibraryFolderWatching.swift` (the one protocol both watchers implement). Then `LibrarySnapshotDiff.swift` — the pure snapshot-comparison core, shared by both watchers and easy to unit test. Then the two implementations: `LocalFolderWatcher.swift` (DispatchSource + debounce + rescan; note the private actor holding all mutable state) and `UbiquityLibraryWatcher.swift` (the NSMetadataQuery/iCloud version — same protocol, so nothing downstream knows the difference). `LibraryLocation.swift` decides which one you get. `ImportService.swift` is a standalone: copy files in, dedupe by name+hash, let the watcher notice. Playlists get the same files-first treatment: `PlaylistFileFormat.swift` (pure `.m3u8` serialize/parse), `PlaylistFileStore.swift` (atomic file I/O under `Playlists/`), and `PlaylistFolderWatcher.swift` (a one-directory sibling of `LocalFolderWatcher`).

### 3. `MetadataImport/` + `LibraryStore/` — diffs become rows (20 min)

`MetadataReader.swift`: one async function, AVFoundation reads ID3 tags. `ArtworkStore.swift`: content-addressed artwork files (SHA-256 → `<id>.img`). Then the heart: `LibraryIndexer.swift` — a `@ModelActor` that consumes watcher diffs and upserts `Track` rows. Read `upsert(_:)` carefully: the skip-unchanged check (size + modified date + download state) is what makes re-indexing cheap, and the download-state re-read is how iCloud placeholder files get their real metadata after downloading.

### 4. `AppFeatures/LibraryCoordinator.swift` — where it's all wired (15 min)

The composition root. `make()` resolves cloud-vs-local, builds the container/watcher/artwork store/player/now-playing bridge, and `start()` runs the pipeline: `for await changes in watcher.changes() { await indexer.apply(changes) }`. That one loop **is** the app's data flow. Also here: `LibraryGroups.swift` — how Artists and Albums exist without being stored (pure functions over `[Track]`), `PlaylistOps.swift` — every playlist mutation in one place, and `PlaylistFileSync.swift` — the two-way bridge that makes `.m3u8` files under `Playlists/` the truth for playlists (ops write files after every save; startup and folder events reconcile SwiftData to match).

### 5. `PlaybackEngine/` — the soul (45 min, the best code in the repo)

`PlayQueue.swift` first: a **pure value type** owning play order, shuffle (current track pinned at head, rest shuffled), repeat semantics, and the `upNext` preload answer. No AVFoundation anywhere — which is why it has ~50 exhaustive unit tests. Then `PlayerController.swift`: the `@MainActor` bridge from that pure queue to a real `AVQueuePlayer`. The core invariant: **the player only ever holds current + next**; the queue is the single source of truth, and `syncPlayerItems(fullRebuild:)` reconciles. Read `handleItemDidEnd()` last — repeat-one's "preloaded duplicate" trick and end-of-queue re-arming are the subtlest logic in the app, and both comments explain a bug that real testing caught.

### 6. `NowPlaying/NowPlayingBridge.swift` — the system integration (15 min)

One class covers the iOS lock screen/Control Center AND Mac media keys. Two hard-won lessons are documented inline: the `withObservationTracking` scope deliberately excludes `currentTime` (else it rewrites the system dict via XPC twice a second), and the `MPMediaItemArtwork` closure must be `@Sendable` (MediaPlayer calls it on its own queue; a main-actor closure traps under Swift 6 — this crashed the app until exploratory testing caught it).

### 7. The UIs (30 min, skim)

Shared iOS-flavored views in `AppFeatures/` (`SongsListView`, `AlbumDetailView`, `PlaylistDetailView`, `NowPlayingView`, `MiniPlayerBar`), composed by `RootTabView` (note the native `tabViewBottomAccessory` for the mini player). The Mac app (`Apps/macOS/Sources/`) is its own shell on the same package: `MainWindow.swift` (split view + sidebar), `SongsTableView.swift` (the sortable table; double-click = `primaryAction`), `PlayerBarView.swift` (the iTunes-style top bar). `DesignSystem/` holds the shared tokens — `ArtworkImage` is worth a read for the downsampling thumbnail cache.

## The tests as documentation

`Packages/OldPodKit/Tests/OldPodKitTests/` — `PlayQueueTests` + `PlayQueueEdgeCaseTests` are executable specs for every shuffle/repeat rule; `LibraryIndexerTests` documents the skip/re-read contract; `PlayerControllerIntegrationTests` plays real audio through real `AVQueuePlayer`. `Apps/iOS/UITests/` drives the actual app (`make uitest`).

## Recurring conventions

- **`@Model` never crosses an actor**: value snapshots (`PlayableTrack`) or `PersistentIdentifier`s travel instead (see CLAUDE.md).
- **Read once, store**: metadata and duration are read at import time, never at render time.
- **Protocol seams at the platform/system boundaries** (`LibraryFolderWatching`), pure value types for logic (`PlayQueue`, `LibrarySnapshotDiff`), actors for shared mutable state.
- Every "why is this weird?" has a comment naming the failure it prevents — the codebase was reviewed and exploratory-tested, and the scars are documented where they happened.
