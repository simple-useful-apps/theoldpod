# theoldpod

A music player for people who own their music.

theoldpod is a pair of apps — iPhone and Mac — that play the MP3s you already have. There is no store, no streaming, no account to create, no ads, and no server anywhere. Your library is a folder of files; iCloud Drive keeps the two apps looking at the same folder. Drag an album in from the Finder and it's on your phone.

It works the way music software used to: Artists, Albums, Songs, Playlists. Pick something. It plays.

## Principles

- **Files first.** The MP3s are the single source of truth. The app's database is just an index and can always be rebuilt from the folder. Nothing is ever locked in.
- **Offline is the default.** No connection needed to play. iCloud is used only to sync files between your devices; with no iCloud account at all, the library is simply local.
- **Calm.** No badges, no upsells, no recommendations, no analytics. The app wants nothing from you.
- **Native on each platform.** The iPhone app is a real iPhone app; the Mac app is a real Mac app — sidebar, song table, media keys, mini player.

## Building

Requires macOS 26, Xcode 26, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make gen        # generate TheOldPod.xcodeproj from project.yml
make test       # package unit tests
make run-ios    # build + launch in the iOS simulator
make run-mac    # build + launch the Mac app
make uitest     # iOS UI test suite
```

Nearly all code lives in the local Swift package `Packages/OldPodKit`; the app targets in `Apps/` are thin shells. iCloud sync requires an Apple Developer Program membership — see [docs/ICLOUD.md](docs/ICLOUD.md). Without it, both apps use a local library folder (still visible in the Files app on iOS).
