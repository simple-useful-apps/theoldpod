---
name: build-run
description: Canonical build/test/run commands for theoldpod (both platforms). Use before building, testing, launching, or screenshotting either app — never rediscover xcodebuild/simctl flags.
---

# Building and running theoldpod

All commands run from the repo root. Prefer the Makefile targets; the raw commands are documented for when you need to deviate.

**Prerequisite check:** `xcode-select -p` must print an `Xcode.app` path. If it prints `CommandLineTools`, full Xcode is not active — only `swift build --package-path Packages/OldPodKit` works (CLT lacks the Swift Testing module, XCTest, #Preview macros, and all simulators); stop and tell the user to install Xcode.

## Fast inner loop (no simulator, no project generation)

```sh
make test          # swift test --package-path Packages/OldPodKit
```

Use this for all `OldPodKit` logic work. Adding/removing files inside the package needs **no** project regeneration.

## Project generation

```sh
make gen           # xcodegen generate → TheOldPod.xcodeproj
```

Required after any change to `project.yml` (targets, entitlements, Info.plist properties) and after adding files under `Apps/`. The `.xcodeproj` is generated and gitignored — never edit it directly.

## iOS (simulator)

```sh
make ios           # build for simulator, unsigned
make run-ios       # build + boot simulator + install + launch
make screenshot    # simctl screenshot → .build/shot.png (verify UI with Read)
```

Raw equivalents (simulator name comes from `SIM ?= iPhone 17` in the Makefile; run `xcrun simctl list devices available` if it's missing and pass `SIM="<name>"`):

```sh
xcodebuild -project TheOldPod.xcodeproj -scheme TheOldPod-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath .build/DerivedData build CODE_SIGNING_ALLOWED=NO
xcrun simctl boot "iPhone 17" || true   # fails harmlessly if already booted
xcrun simctl install booted .build/DerivedData/Build/Products/Debug-iphonesimulator/TheOldPod.app
xcrun simctl launch --console-pty booted com.mattreed.theoldpod   # streams app stdout/logs
```

## macOS

```sh
make mac           # build the Mac app
make run-mac       # build + launch (open .build/DerivedData/Build/Products/Debug/TheOldPod.app)
```

For stdout/log capture, exec the binary directly instead of `open`:
`.build/DerivedData/Build/Products/Debug/TheOldPod.app/Contents/MacOS/TheOldPod`

## Formatting

`swiftformat <files-you-touched>` before reporting done.

## What cannot be verified here

- iCloud Drive sync (simulator iCloud is flaky; real test = Mac + physical iPhone).
- Real lock-screen behavior and Mac media keys (need device/manual check).
- Anything needing signing: Mac builds with iCloud entitlements require `DEVELOPMENT_TEAM`; simulator builds always use `CODE_SIGNING_ALLOWED=NO`.
