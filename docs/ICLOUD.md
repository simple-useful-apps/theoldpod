# Turning on iCloud (M5 follow-up, once you have a paid Apple Developer membership)

M5 makes the whole codebase iCloud-capable — `CloudFiles.LibraryLocation.resolve()`,
`UbiquityLibraryWatcher`, and `DownloadRequester` all exist and are exercised by
tests — but **no iCloud entitlement is checked in**, because entitlements
require a paid membership (`DEVELOPMENT_TEAM`) to sign, and this repo needs to
build and run unsigned for everyone without one. Until you flip the switch
below, both apps use the local `Documents/Music` fallback, which is the
currently shipping behavior.

Do this once you have a paid membership:

## 1. Add the entitlements

Both app targets in `project.yml` need an `icloud-services` +
`icloud-container-identifiers` / `ubiquity-container-identifiers` entry
pointing at the same container ID, `iCloud.com.mattreed.theoldpod`.

`TheOldPod-macOS` already has an `entitlements:` block — add to it:

```yaml
entitlements:
  path: Apps/macOS/TheOldPod-macOS.entitlements
  properties:
    com.apple.security.app-sandbox: true
    com.apple.security.files.user-selected.read-only: true
    com.apple.developer.icloud-services: [CloudDocuments]
    com.apple.developer.icloud-container-identifiers: [iCloud.com.mattreed.theoldpod]
    com.apple.developer.ubiquity-container-identifiers: [iCloud.com.mattreed.theoldpod]
```

`TheOldPod-iOS` doesn't have an `entitlements:` block yet — add one:

```yaml
entitlements:
  path: Apps/iOS/TheOldPod-iOS.entitlements
  properties:
    com.apple.developer.icloud-services: [CloudDocuments]
    com.apple.developer.icloud-container-identifiers: [iCloud.com.mattreed.theoldpod]
    com.apple.developer.ubiquity-container-identifiers: [iCloud.com.mattreed.theoldpod]
```

## 2. Set `DEVELOPMENT_TEAM`

Entitlements can't be signed ad-hoc (`CODE_SIGN_IDENTITY: "-"`, the current
macOS setting) or run unsigned on a device. Add your team ID to both targets'
`settings.base`:

```yaml
DEVELOPMENT_TEAM: <YOUR_TEAM_ID>
```

For macOS, also drop `CODE_SIGN_IDENTITY: "-"` and set `ENABLE_HARDENED_RUNTIME: true`
(real distribution/dev signing requires the hardened runtime with the
iCloud entitlement present).

## 3. Regenerate the Xcode project

```
make gen
```

## 4. Bump `CFBundleVersion`

`NSUbiquitousContainers` (already in `project.yml`'s `Info.plist` properties
for both targets, added ahead of time in M5) is cached by iOS/macOS **per
bundle version** the first time an app with a given bundle ID + version runs.
If you've ever run an unsigned build of this app on a device/simulator
before adding the entitlement, bump `CFBundleVersion` (or reinstall fresh) so
the OS re-reads the `NSUbiquitousContainers` dictionary instead of using a
stale cached (absent) mapping.

## 5. First run: folder creation

On first launch with the entitlement present and the user signed into
iCloud, `LibraryCoordinator.make()` calls `LibraryLocation.resolve()`, which
resolves `FileManager.url(forUbiquityContainerIdentifier: nil)` and creates
`<container>/Documents/Music` if it doesn't exist yet — same shape as the
local fallback (`Documents/Music`), just inside the ubiquity container. No
extra code should be needed; this is exercised by the M5 test suite for the
non-iCloud path and by hand for the iCloud path (there's no way to fake a
signed ubiquity container in `swift test`).

## 6. Physical-device test recipe

1. Build and run on a physical device signed with your team (a simulator
   can exercise the code path but won't show real Finder/Files-app iCloud
   Drive sync).
2. On the Mac (or `iCloud.com`, or an iOS Files app with an iCloud Drive
   toolbar item enabled), open iCloud Drive and find **"The Old Pod"** —
   that's `NSUbiquitousContainerName`. Open it and confirm a `Music` folder
   exists (created by step 5 above).
3. Drag an MP3 into `iCloud Drive/The Old Pod/Music` from the Finder.
4. Within a few seconds it should sync and appear on the iPhone: the
   `UbiquityLibraryWatcher`'s `NSMetadataQuery` should fire a `DidUpdate`,
   the file should show the `icloud.and.arrow.down` glyph in the Songs list
   until downloaded, and tapping it should call
   `DownloadRequester.requestDownload(of:)` and then play once the download
   completes.
5. Delete the file from the Finder and confirm it disappears from both
   apps' libraries (the watcher emits a `.remove`).
