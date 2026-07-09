# v1.1 goal prompt — five workstreams, no Apple Developer account required

You are working on theoldpod (this repo). Read `CLAUDE.md`, `GOAL.md`, and `docs/BACKLOG.md` first; load the `design-language` skill before any UI work. Everything below is verifiable locally: `make test` (package), `make uitest` (iOS, 8 tests), `make mac-uitest` (Mac, 7 tests) must stay green throughout, extended wherever behavior changes. Two consecutive green UI-suite runs after UI changes. Commit per workstream with evidence in the message; push to origin.

Established session facts: fixtures are 4 tagged MP3s (seeded in both app containers); Mac visual verification = CGWindowList window IDs + `screencapture -l<id>` + reading the PNG (Screen Recording is granted); the Mac app has a `--uitest-reset-playlists` launch-arg test hook; macOS XCUITest reads text via `.value` not `.label`; swiftformat strips `@Suite`; UI tests cannot run while the screen is locked.

## 1. Dark-mode visual sweep (both platforms)

Nothing has ever been checked in dark mode.

- iOS: `xcrun simctl ui booted appearance dark`, then drive the existing UI-test suite (its `XCTAttachment` screenshots become the dark captures) and/or `make run-ios` + `make screenshot` for reachable states. Sweep every screen the light-mode sweep covered.
- Mac: do NOT change the user's system appearance. Add a test-only launch argument (pattern exists: `--uitest-reset-playlists` in `MacRootView`/`TheOldPodApp`): `--uitest-appearance-dark` → `NSApp.appearance = NSAppearance(named: .darkAqua)` at startup. Launch with it, capture the same 9 states as the light sweep (Songs idle/playing, Artists/Albums filtered/unfiltered, playlist, Mini Player, narrow width).
- Judge against the design-language skill: hardcoded colors, invisible hairlines, artwork-placeholder contrast, LCD legibility on the bar material. Fix whatever's broken; re-capture to confirm. System colors/materials should make most screens free — the goal is proof, not assumption.

## 2. Playlist files (.m3u8 in the library folder)

Removes v1's biggest asterisk ("playlists don't sync") in a way that needs no iCloud today and syncs for free once entitlements arrive — playlists become files, honoring GOAL.md's "the store is always rebuildable from the folder."

- New `PlaylistFiles` support in `CloudFiles` (or a sibling module): playlists serialize to `<libraryRoot>/Playlists/<name>.m3u8` — `#EXTM3U`, one `#EXTINF:<seconds>,<title>` + library-root-relative path per entry. Filename = playlist name sanitized for the filesystem (strip `/:`); document the sanitization.
- **Files are the truth.** App mutations (create/rename/delete/add/remove/reorder via `PlaylistOps`) write the file synchronously after the SwiftData save. At startup and on `Playlists/` directory changes (extend the existing watcher patterns — `LocalFolderWatcher` handles `*.mp3` only today), reconcile SwiftData to match the files: new file → new playlist; missing file → delete playlist; changed file → replace entries. External rename = delete + create (acceptable; note it).
- Entries referencing paths with no matching `Track` stay as dangling entries (the UI already renders "File missing").
- Tests: round-trip (ops → file → wipe store → reconcile → identical playlists), external-edit reconciliation, sanitization, dangling paths. Extend the iOS/Mac playlist UI tests only if flows changed.
- Migration: on first launch with this build, export existing SwiftData playlists to files before reconciling (don't delete anyone's playlists).

## 3. Up Next queue screen (both platforms)

The classic iPod queue view; `PlayQueue.jump(to:)` has been waiting for it.

- `PlayQueue` gains `remove(at:)` (bounds-checked; removing before `currentIndex` shifts it; removing current advances like end-of-track skip — spec the edge cases in tests). `PlayerController` gains `jump(to:)` and `removeFromQueue(at:)` wrappers that re-sync the AVQueuePlayer preload.
- Shared `UpNextView` in `AppFeatures`: dense list of `queue.items` from `currentIndex` forward, current track marked with the speaker glyph, tap (iOS) / double-click (Mac) jumps, swipe-delete (iOS) / delete key + context menu (Mac) removes. Empty state per design language.
- iOS: reachable from the Now Playing sheet (toolbar/list button). Mac: popover from a new queue button in the player bar's right cluster + a "Show Up Next" item in the Playback menu.
- Tests: PlayQueue remove/jump edge cases (unit); one UI test per platform (play all → open Up Next → jump to a later track → bar shows it).

## 4. Small backlog items (three, all decided)

- **Download badge coverage**: extract the trailing status view (speaker glyph / `icloud.and.arrow.down` / duration) used by `SongsListView` rows into a shared component and use it in album, playlist, and artist-detail rows on both platforms.
- **Custom accent**: add an `AccentColor` to both asset catalogs derived from the icon — light `#3E5F9C`, dark variant lightened for contrast (~`#8FADD9`, matching the landing page's dark accent). Verify tinted controls (shuffle/repeat active state, selection highlights, progress ring) in both appearances during workstream 1's sweep. One accent, per the design language.
- **Batch Play Next semantics**: decided — first track of the batch plays first even on an empty queue. Fix `PlayerController.playNext(_ tracks:)`'s empty-queue path and update the unit test that currently pins the last-track-first behavior (`docs/BACKLOG.md` "Product decisions pending" — remove the entry).

## 5. CI (GitHub Actions)

`.github/workflows/ci.yml`, `macos-15`-or-newer runner, on push/PR to main. Keep macOS minutes lean (private repo, 10× multiplier): single job — checkout, `brew install xcodegen`, `xcodegen generate`, `swift test --package-path Packages/OldPodKit`, plus `xcodebuild build` for both app targets with `CODE_SIGNING_ALLOWED=NO`. Cache SPM artifacts (`.build`). NO simulator UI tests in CI (flaky + expensive) — they stay local via the Makefile. Verify by pushing and watching the run complete green (`gh run watch`).

## Order

2 and 3 both touch playback/AppFeatures — do 2 → 3 sequentially. 4's small items can ride with adjacent workstreams (badge + accent land before the sweep re-captures; Play Next fix anytime). 1's sweep runs LAST so it captures the accent and new screens. 5 is independent — land it first so every subsequent push gets CI. Update `docs/BACKLOG.md` and `docs/TOUR.md` for anything that changes their claims, and close with a summary of pixels captured, bugs found/fixed, and suite counts.
