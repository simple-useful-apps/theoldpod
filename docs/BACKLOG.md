# Backlog

Known items deliberately deferred from v1, mostly surfaced by the M6 full-codebase review. None block daily use.

## Performance (matters at multi-thousand-track libraries)

- **Memoize `LibraryGroups.albums/artists`** — recomputed over all tracks on every body evaluation of the Albums/Artists screens (tens of ms at 5–10k tracks; repeatable jank on tab reselect/nav pop). Needs a cheap library-revision token to key a cache; design it rather than bolt on `tracks.count`.
- **Artwork import cost** — indexing loads + SHA-256-hashes identical embedded art once per track (12× per 12-track album). Short-circuit on already-seen digests if initial indexing of huge libraries feels slow.
- **LocalFolderWatcher rescans** — each debounced FS event walks the whole tree twice (files scan + directory scan). Merge into one enumeration if large local libraries make this noticeable.

## Behavior polish

- **Repeat-mode toggle race** — toggling repeat at the exact moment a repeat-one track ends can audibly cut to the next track (the mismatch branch full-rebuilds mid-play). Rare, self-healing; fix by capturing repeatMode at end-event time.
- **Download badge coverage** — undownloaded-track glyph shows in the Songs list and Mac table but not in album/playlist/artist rows. Extract a shared track-row trailing view.
- **Playlists don't sync between devices** (by design in v1 — SwiftData is local-only). v2 path: export/import `.m3u8`-style files living in the library folder; `PlaylistEntry.trackPath` string references were chosen to keep this straightforward.

## Verification gaps (from the exploratory-testing session)

- **Mac right-click context menus** (songs table, playlist rows) resist synthetic events — NSMenu tracking wants real HID input. One human right-click confirms them; a Mac XCUITest target (mirroring `Apps/iOS/UITests`) is the automated fix and would also give trusted double-click/menu events for future Mac exploration.
- **VoiceOver on the Mac**: explicit `.accessibilityLabel`s are on all transport buttons and the playlist "+" now, and the same shared views verify labeled on iOS — but System Events' legacy AX bridge is too lossy to confirm on macOS (some SwiftUI buttons surface unlabeled, some not at all). One ⌘F5 VoiceOver pass, or the Mac XCUITest target above, settles it.

## Test health

- `LocalFolderWatcherTests.deletingAFileEmitsARemoveWithItsRelativePath` intermittently times out waiting for a real DispatchSource FS event when run in isolation (pre-existing; bisected as unrelated to the M6 changes). Consider a filesystem-event test double if it flakes in CI.

## Cleanup

- Artwork filename pattern `"\(id).img"` is inlined in ArtworkStore, NowPlayingBridge, and the artwork thumbnail loader — acceptable duplication until the naming ever changes; a shared helper needs a cross-module home first.
- "N songs · duration" header line duplicated across album/playlist headers (iOS + Mac).
- `PlayQueue.jump(to:)` has no UI caller yet — kept for the future queue screen.
- `NowPlayingBridge.deactivate()` / `LibraryCoordinator.stop()` have no callers (coordinator is a process-lifetime singleton); wire them up if a teardown path ever exists.

## Product (post-v1, per GOAL.md non-goals)

- A considered custom accent blue (M6 note in design-language skill) — could derive from the icon's #3E5F9C now that it exists.
- Queue screen ("Up Next"), smart playlists, EQ, gapless refinement, CarPlay — explicitly out of v1 scope.
