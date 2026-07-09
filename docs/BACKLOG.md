# Backlog

Known items deliberately deferred from v1, mostly surfaced by the M6 full-codebase review. None block daily use.

## Performance (matters at multi-thousand-track libraries)

- **Memoize `LibraryGroups.albums/artists`** — recomputed over all tracks on every body evaluation of the Albums/Artists screens (tens of ms at 5–10k tracks; repeatable jank on tab reselect/nav pop). Needs a cheap library-revision token to key a cache; design it rather than bolt on `tracks.count`.
- **Artwork import cost** — indexing loads + SHA-256-hashes identical embedded art once per track (12× per 12-track album). Short-circuit on already-seen digests if initial indexing of huge libraries feels slow.
- **LocalFolderWatcher rescans** — each debounced FS event walks the whole tree twice (files scan + directory scan). Merge into one enumeration if large local libraries make this noticeable.

## Behavior polish

- **Repeat-mode toggle race** — toggling repeat at the exact moment a repeat-one track ends can audibly cut to the next track (the mismatch branch full-rebuilds mid-play). Rare, self-healing; fix by capturing repeatMode at end-event time.
- **Download badge coverage** — undownloaded-track glyph shows in the Songs list and Mac table but not in album/playlist/artist rows. Extract a shared track-row trailing view.
- ~~Playlists don't sync between devices~~ — retired in v1.1: playlists now live as `.m3u8` files under `<libraryRoot>/Playlists` (`PlaylistFileSync`), so they ride along with whatever syncs the library folder. Known edges, all accepted: external file rename reads as delete+create (new `createdAt`); non-atomic in-place edits may not be noticed until next launch; same-name playlists merge on reconcile.

## Verification gaps

- **VoiceOver on the Mac**: explicit `.accessibilityLabel`s are on all transport buttons and the playlist "+", and the Mac XCUITest suite drives everything through the accessibility layer — but a human ⌘F5 VoiceOver listen remains the gold standard for reading order and announcements.
- ~~Mac right-click context menus~~ — retired: `make mac-uitest` drives them with trusted events (Play / Play Next / Add to Playlist submenu all verified, triple-green).

## Test health

- `LocalFolderWatcherTests.deletingAFileEmitsARemoveWithItsRelativePath` intermittently times out waiting for a real DispatchSource FS event when run in isolation (pre-existing; bisected as unrelated to the M6 changes). Consider a filesystem-event test double if it flakes in CI.

## Product decisions pending

- **Batch "Play Next" on an empty queue starts on the batch's LAST track** (the first insert into an empty queue acts like replace-at-0, then the rest stack in front). Pre-existing behavior, preserved and pinned by a unit test during the simplify pass — decide whether first-track-first is the better semantic.
- **iOS/Mac PlaylistDetailView remain two implementations** of one concept (~230 lines each). Shared components (PlayShuffleButtons, LibraryText, TrackContextMenuContent) now cover the drift-prone parts; full unification deferred as a larger refactor.

## Cleanup

- Artwork filename pattern `"\(id).img"` is inlined in ArtworkStore, NowPlayingBridge, and the artwork thumbnail loader — acceptable duplication until the naming ever changes; a shared helper needs a cross-module home first.
- "N songs · duration" header line duplicated across album/playlist headers (iOS + Mac).
- `PlayQueue.jump(to:)` has no UI caller yet — kept for the future queue screen.
- `NowPlayingBridge.deactivate()` / `LibraryCoordinator.stop()` have no callers (coordinator is a process-lifetime singleton); wire them up if a teardown path ever exists.

## Product (post-v1, per GOAL.md non-goals)

- A considered custom accent blue (M6 note in design-language skill) — could derive from the icon's #3E5F9C now that it exists.
- Queue screen ("Up Next"), smart playlists, EQ, gapless refinement, CarPlay — explicitly out of v1 scope.
