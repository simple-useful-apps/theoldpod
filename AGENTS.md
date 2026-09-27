# theoldpod

Local-first MP3 player: an iPhone app + a Mac app that share a user-visible iCloud Drive folder of music files. No cloud services, no accounts, no ads. Read `GOAL.md` before making product or design decisions — it is the source of truth for scope and feel.

## Layout

- `project.yml` — XcodeGen spec. The `.xcodeproj` is generated and gitignored; **never edit the xcodeproj**. After changing targets/entitlements/plist keys: `make gen`.
- `Apps/iOS/`, `Apps/macOS/` — thin app targets (entry point + platform shell only).
- `Packages/OldPodKit/` — one local SPM package holding nearly all code. Targets: `Domain`, `LibraryStore`, `MetadataImport`, `CloudFiles`, `PlaybackEngine`, `NowPlaying`, `DesignSystem`, `AppFeatures`. Adding files here needs no project regeneration.
- `Fixtures/` — small generated MP3s for tests.

## Build / test / run

Use the `build-run` skill (`.Codex/skills/build-run/`) or the Makefile — don't rediscover xcodebuild flags. Fast inner loop: `make test` (package tests, no simulator).

## Rules

- Swift 6 strict concurrency is on. `PlayerController` is `@MainActor`; SwiftData work happens on the `LibraryIndexer` `@ModelActor`; never pass `@Model` instances across actors (use `PersistentIdentifier`).
- Artists/Albums are derived groupings of `Track`s, never stored entities.
- Track durations and metadata are read once at import (`AVURLAsset.load(...)`) and stored — never computed at render time.
- The library folder's files are the source of truth; the SwiftData store must always be rebuildable from them.
- iCloud code paths (M5) must degrade gracefully: no iCloud account → local `Documents/Music` fallback.
- UI work: load the `design-language` skill first (once it exists, from M1 on).
