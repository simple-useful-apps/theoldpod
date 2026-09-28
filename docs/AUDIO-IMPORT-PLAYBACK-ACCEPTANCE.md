# WMA import and audiobook playback repair

Requested September 14, 2026. Implemented with the verification scope and remaining checks recorded below.

## Subsequent TestFlight upload

At the user's explicit request, iPhone version **1.0 (7)** was archived and uploaded
successfully on September 14, 2026 at 21:57 Eastern. Apple reported
`Uploaded package is processing`, `Upload succeeded`, and `EXPORT SUCCEEDED`.
Availability to testers after processing has not been independently confirmed.
Archive: `.build/TheOldPod-iOS-audio-repair-7.xcarchive`.
Evidence: `.build/testflight-7-archive.log`, `.build/testflight-7-upload.log`.
This release step changed only the iPhone build number, not the reviewed product
code. The acceptance limitations below remain; this upload does not establish
physical-device or cloud behavior. The earlier statements about no upload refer
to the implementation/acceptance pass before this subsequent release request.

## Scope

- Mac import automatically converts supported, unprotected WMA files to M4A locally, without requiring a user-installed converter. Originals remain unchanged.
- Preserve available title/artist/album/track metadata and artwork where supported. Show conversion progress and per-file errors; never present an incomplete output as imported music.
- iPhone audiobook ±15-second controls and the chapter slider must use the playable chapter's real duration rather than a stale zero-length queue snapshot.
- Prepare missing chapter metadata in the background as soon as a book reaches the library (including a book first synced to iPhone as iCloud placeholders), not when it is opened; surface only a failure, with Try Again. Preserve already-known chapter lengths and never display an unknown length as a measured zero.
- Preserve existing library, deletion, playback-speed, and resume work. Do not alter the user's real media during acceptance.

## Acceptance targets

Use newly created copies in isolated app libraries. Prefer computer-driven app flows; no unit suite is requested.

1. Import a tagged WMA on Mac through the normal picker and through a folder/drop path. Expect a playable M4A with metadata and an unchanged WMA original.
2. Verify repeated import and filename collisions do not overwrite unrelated files or create avoidable duplicates.
3. Verify unsupported/corrupt WMA reports a useful error, leaves no partial library file, and does not block other files in a mixed import.
4. Verify the Mac app carries its converter and does not execute a Homebrew/system FFmpeg. Verify the iPhone build does not include the helper.
5. Open a book before playing chapters; known lengths should appear, lengths still being read should show a dash rather than 0:00 (with no preparation banner), and offline/unavailable files should be explained.
6. On a long real chapter, pause away from the beginning and exercise +15, -15, and slider seeking. Time, audible position, and saved progress should agree without restarting the chapter.
7. Verify rapid skips, chapter changes, natural advancement, and seeking immediately after load. Preserve paused/playing state and playback speed. The artwork ring is a non-interactive progress display, not a second scrubber.
8. Quit/relaunch and confirm a valid saved chapter position returns. Verify unrelated music playback and imports still work.

## Dependency evidence

The installed Homebrew FFmpeg is a GPL-enabled shared build and is not an appropriate self-contained app dependency. The planned helper is built from a pinned official source archive with only needed, non-GPL components.

- [FFmpeg licensing and distribution guidance](https://ffmpeg.org/legal.html)
- [Official FFmpeg source downloads](https://ffmpeg.org/download.html)
- [Apple sandbox inheritance requirements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)
- [Apple playback readiness and seeking guidance](https://developer.apple.com/documentation/avfoundation/controlling-the-transport-behavior-of-a-player)

Downloaded FFmpeg 8.1.2 source archive SHA-256:
`464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c`.
It matches the installed Homebrew source formula checksum. The archive is under
`.build/vendor-sources/ffmpeg-8.1.2.tar.xz`; no developer-installed binary is to be bundled.

## Results

### Final revision and method

Final Swift-source aggregate fingerprint:
`ab820a70f15a042cdd50281bac68facdaa22fc7f2cc455f29fabc6e85621ce44`.

Both canonical builds passed (`make ios`, `make mac`), with logs at
`.build/wma-ios-build.log` and `.build/wma-mac-build.log`. No unit suite was run.
Acceptance used the actual Mac app and iPhone 17 simulator via Computer Use,
with generated WMA files and copies of two real Manning chapters. No user media
was deleted or modified, and no TestFlight upload was performed in this pass.

The runtime blocked spawning fresh Reviewer/Tester roles. As a fallback, the
planner performed read-only review and targeted rechecks, the scout independently
checked packaging/conversion and the final bundle, and primary drove GUI tests.
All reported review findings were fixed by the implementation worker. Final
targeted review reported no outstanding findings. This is not a claim that fresh
native Reviewer and Tester roles ran.

### Mac GUI results

- Direct WMA selection and sandboxed conversion passed with `/usr/bin:/bin:/usr/sbin:/sbin`
  as the app's PATH. Converted audio appeared with title, artist, album, and 1:30
  duration; actual playback clock advanced from 0:00 to 0:15.
- Testing found a disabled WMA picker. A Mac-only imported audio type declaration
  fixed it. Development testing required registering the rebuilt app with
  LaunchServices and restarting; the corrected normal picker then accepted WMA.
- Mixed-folder import passed: uppercase WMA in a nested folder and native M4A
  imported, while `broken.wma` produced a named, readable error. Valid imports
  remained available and the paused audiobook's position was unchanged.
- Importing a different M4A with the same destination filename retained both
  tracks. Reimporting the original WMA left the four-song count unchanged.
- WMA book import showed `Converting 01-First chapter.wma (1 of 2)` and produced
  one book containing both numbered chapters, total 3:00. Identical audio bytes
  under different chapter filenames were intentionally retained.
- Manning chapter lengths appeared before either chapter played: 29:05 and
  36:17, total 1:05:21.
- Native slider accessibility adjustment sought to 3:08. Paused +15 changed
  187.768 seconds to 202.768; -15 returned to 187.768. Three successive +15
  presses reached 232.768 seconds, exactly 45 seconds ahead.
- Playback continued from the selected position at 1.5×. Seeking near the end
  and playing naturally advanced to chapter 2 with a live clock; its +15 worked.
- Restart restored chapter 2 at 41.214 seconds, paused, at 1.5×. On the final
  rebuilt executable, +15 advanced that restored position to 56.213 seconds.

### iPhone simulator GUI results

- Final build installed and launched using an isolated library. Computer control
  initially returned `noWindowsAvailable` for coordinates, then recovered. These
  are simulator results, not physical-device results.
- Before playback, Books showed total 1:05:21 and chapter lengths 29:05/36:17.
- Paused +15 changed 0:09 to 0:24 rather than restarting the chapter.
- The slider was enabled. Accessibility value assignment alone moved its thumb
  without committing playback; a subsequent native touch/drag at that thumb
  committed the seek. Midpoint seek showed 14:32; Play advanced to 14:33 and
  then 14:41, confirming actual player time rather than only a changed label.
- -15 changed paused 14:41 to 14:26; three successive +15 presses reached 15:11.
- Set speed to 1.5×, sought to 28:47 using the slider, and played through the
  chapter boundary. Chapter 2 began with an advancing clock; paused +15 changed
  approximately 0:20 to 0:35.
- Terminate/relaunch restored chapter 2 at 0:35, paused, with 1.5× speed intact.
- **Continuous finger dragging is not fully verified.** The automation's long
  drags repeatedly appeared to apply only their starting coordinate. Native
  slider seek commitment and subsequent playback were verified, but that is not
  sufficient evidence of an ordinary start-to-end finger drag on a physical phone.

### Dependency verification

- Real helper conversion produced an 89.977755-second playable M4A with source
  title, artist, album, and track number; repeat conversions were byte-identical.
- Original WMA SHA-256, size, and modification time matched the baseline after
  GUI imports. Independent inspection found both arm64 and x86_64 helper slices
  and only Apple system dynamic dependencies.
- Signed helper's entitlements are exactly App Sandbox plus inherited sandbox.
  Parent-app execution passed. Direct standalone launch of that inherited helper
  is not a valid acceptance path; standalone diagnostics used the unsigned build.
- Mac app contains exact FFmpeg source/license/configuration materials; iOS app
  excludes the helper and those resources. WMA conversion/picker support is Mac-only.
- Strict local signature trust verification reports `CSSMERR_TP_NOT_TRUSTED` for
  the development certificate. Xcode signing and actual sandboxed app/helper
  execution passed, but distribution/notarization trust was not verified.

### Remaining checks — not claimed as passed

- Normal continuous finger dragging and all slider boundary gestures on a
  physical iPhone; Mac mouse dragging (Mac accessibility adjustment passed).
- Physical Mac-to-iPhone iCloud transfer, cloud-only chapter preparation,
  eviction/re-download, offline/retry behavior, and full-book bounded preparation.
- Runtime reproduction with deliberately stale zero-duration queue metadata,
  failed/unavailable initial chapter, interrupted/exhausted seeks, and preservation
  of existing bookmarks in those failure paths. These received code review, not
  an end-to-end fault-injection run.
- Lock-screen controls, media keys, calls/audio interruptions, and background
  behavior on real devices. Relaunch/resume was tested as described above.
- Active conversion cancellation, artwork preservation/fallback, genuine DRM,
  WMA Pro/Lossless fixtures, and Intel execution. Tested input was WMAv2 without
  artwork. No claim of DRM removal is made.
- Finder drag/drop entry point (file/folder pickers passed), long-running UI
  responsiveness beyond the observed conversion progress, and raw output-file
  partial-publication checks in the signed GUI path (standalone corrupt input
  failed without producing a usable output).
- Distribution certificate trust/notarization and TestFlight delivery of this
  revision. No release upload was requested or performed for this pass.

### Short physical-iPhone follow-up

1. Add a book on the Mac and let it sync. Without opening it on iPhone, wait a
   moment, then open it; verify lengths are already there. Repeat with a cloud-only book.
2. Pause around one minute. Tap +15, then -15; confirm the exact change and no restart.
3. Drag the slider with a finger to the middle, start playback, then drag near
   the end. Confirm the spoken content changes along with the clock.
4. Repeat at 1.5×, allow the next chapter to start, then try +15 and the slider again.
5. Close/reopen the app; confirm chapter, position, and speed. Check lock-screen
   skips and an offline/unavailable chapter without losing an existing bookmark.

### Prepared fixtures and preliminary packaging inspection

- Generated 90-second WMAv2 source: `.build/audio-acceptance-inputs/WMA/acceptance.wma`.
  Title `WMA Acceptance`, artist `The Converter`, album `Import Checks`, track 2.
  Source SHA-256 `1e14f837a028c90e6deb9dbfc113fb5eeb01f8aab0573b1a1b1236b4f627b283`;
  baseline modification time `1789432630`, size `1552834` bytes.
- Mixed folder includes uppercase `.WMA`, native M4A, and deliberately invalid
  `broken.wma`. A separate 95-second native `acceptance.m4a` exercises collisions.
- WMA book fixture has two numbered chapter files. Real Manning copies include
  chapter 1 (`1744.610` seconds) and chapter 2 (`2176.769002` seconds), independently
  measured with ffprobe. User originals remain outside the acceptance library.
- Preliminary `file`/`otool -L` inspection of the built helper confirms arm64 and
  x86_64 slices and only Apple system dynamic dependencies. This does not yet
  establish signed-app execution, successful conversion, or Intel runtime behavior.

## September 18: real-library discovery repair

### Reproduced before repair

- User-supplied `Sleep_3_SpiegelImSpiegel.wma` is valid WMAv2 (641.706 seconds).
  Its already-converted M4A existed in the actual iCloud Music folder, with AAC
  audio, title `Spiegel Im Spiegel`, artist `Sergej Bezrodny`, and duration
  641.683 seconds. Neither restarting the Mac app nor Refresh Library displayed it.
- Direct Spotlight inspection can find the converted file; the initial sandboxed
  `mdls` failure was not evidence that Spotlight lacked it. The observable failure
  is between file discovery and the app's index, not failed WMA conversion.
- During diagnostic picker use, selection failed and the surrounding folder was
  inadvertently imported. The app was quit immediately. With explicit user approval,
  exactly `Track1_Body_Scan.mp3`, `Track2_Urge_Surfing.mp3`, and
  `Track3_Mountain_Meditation.mp3` were selected in the Mac app and moved to Trash.
  Their disappearance was verified in both the UI and library folder. No source
  originals were deleted; the two intended Sleep MP3s and converted M4A remain.
- Original WMA baseline: 15,467,522 bytes, modification epoch 1753930053,
  SHA-256 `3d03628bfbca47487a4b32c5f2ad80e941dc38361179030630a203e707c3d257`.

### Repair verification

- Mac and iOS builds passed; SwiftFormat and `git diff --check` passed. No unit
  suite was run.
- Independent computer-use acceptance on the real iCloud-backed Mac library
  confirmed the existing converted file appeared after launching the updated app,
  without reimport: `Spiegel Im Spiegel / Sergej Bezrodny / Alina / 10:42`.
- Independent review identified an initial-scan error recovery issue. The root is
  now watched before scanning, with three cancellation-aware bounded initial retries.
  Targeted re-review is clear; both platform builds passed again. Final watcher
  SHA-256: `56f95e726a8213e3ce855d9432d2d6a50673e3ddf68f951dc7badcb1df7df572`.
- Real-app playback advanced from 0:00 to 0:05; paused at 0:10. Restart retained
  the track and paused position. Refresh completed and advanced Last checked.
- Exact-file Add Music reimport passed. Cmd-Shift-G with the full original WMA
  path produced a visibly selected filename before Open; the app showed
  `Converting Sleep_3_SpiegelImSpiegel.wma (1 of 1)`. After completion, there were
  still exactly three music rows and one converted M4A: no duplicate appeared.
  The original WMA hash, size, and modification time matched the baseline.
- Final rebuilt app passed an independent quit/relaunch and refresh check:
  exactly the three intended songs remained, correct Spiegel metadata/duration,
  Last checked advanced, no error. App was left open and paused at 0:10.
- Finder drag-and-drop, physical-iPhone propagation, genuine cloud eviction and
  redownload, and forced filesystem-scan failures have not been exercised in this
  repair pass. These are not claimed as passed.
