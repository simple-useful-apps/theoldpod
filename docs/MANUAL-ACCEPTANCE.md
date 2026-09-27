# iPhone manual acceptance script

Allow about 20 minutes. Record the TestFlight version/build and your iOS version.
Latest uploaded target: version 1.0, build 8, including the artwork cleanup (no circular
overlay, book placeholders for audiobooks), audiobook repairs, deletion, and library polish.
Upload to App Store Connect succeeded on September 15, 2026 at 19:14 Eastern;
Apple reported the package was processing. TestFlight
availability after processing has not yet been confirmed.
Upload evidence: `.build/testflight-8-upload.log`; signed archive:
`.build/TheOldPod-iOS-artwork-8.xcarchive`. Dark mode, smaller iPhones, and
physical-device artwork checks remain unverified.
Use copies of music and disposable playlists: the production app uses your real
iCloud library, and file deletions can propagate to other devices. Do not sign
out of iCloud or delete your real library for these tests.

Prepare two tracks longer than one minute: one MP3 and one M4A. Include the
original M4A that previously would not import. Call the tracks A and B below.

For audiobook features (build 5 onward), use [the audiobook guide](AUDIOBOOKS.md).
Import your Manning download from **Books → Import Book**, give it a title,
and select the folder. Test Resume after switching to music and after force
quitting the app; verify the chapter, position and chosen speed survive. Test
15-second controls while paused and playing. Bookmarks are device-local.

For build 7, prioritize the [audiobook repair follow-up checks](AUDIO-IMPORT-PLAYBACK-ACCEPTANCE.md#short-physical-iphone-follow-up),
especially continuous finger dragging and cloud-only chapter preparation. WMA conversion
is Mac-only; the iPhone plays the resulting M4A files after they sync.

## 1. Import — including the original problem

1. Open Songs, tap Import, and select the MP3 and M4A in Files.
2. Expect both to be selectable and to appear with sensible titles and durations.
3. Play each; expect sound and an advancing time readout.
4. Import the exact same files again. Expect no duplicate rows.
5. Repeat with the original problem M4A. If it fails, note whether it is greyed
   out, selectable but not imported, or imported but unable to play. Record its
   source location, filename/extension, and any error. Keep the file for diagnosis.

## 2. Seeking and transport — highest priority

1. Play A and open full Now Playing by tapping the mini-player title.
2. Drag the scrubber to about 0:30. Expect the thumb, time labels, and audible
   position to agree. Playback should keep advancing after release.
3. Pause. Drag to about 0:45. Expect the position to change without playback.
4. Toggle shuffle on and off. Expect the same track, position, and paused state.
5. Resume and toggle shuffle again. Expect continuous playback without restarting.
6. Pause and tap Next. Expect B at 0:00, still paused. Resume B, wait five seconds,
   and tap Previous. Expect B to restart, not jump to A. Tap Previous again
   immediately; expect A when shuffle is off and A precedes B in the queue.
7. Cycle Repeat: off → all → one → off. Verify the icon/state changes. With Repeat
   One, seek near the end and let the track finish: expect the same track again.
8. Dismiss and reopen Now Playing. Expect the same playback state and time.

The following artwork checks apply to build 8 or later; they are not included in build 7.

9. Play an audiobook chapter with no embedded artwork. Expect a book icon in
   the grey placeholder on full Now Playing and the iPhone mini-player (and in
   the Mac player bar, if testing the companion app), with no circular overlay.
10. Play a music track with no embedded artwork. Expect the existing music-note
    placeholder on each player surface.
11. Play a track or book with embedded artwork. Expect the real artwork, with no
    placeholder icon drawn over it.

## 3. Queue and playlists — long-press gestures

1. With A playing, long-press B in Songs and choose Play Next. Tap Next; expect B.
2. Create a playlist named `Manual Check`. Long-press A and B and use Add to
   Playlist to add each. Expect two songs in the order added.
3. Use the playlist's editing controls to reorder B before A. Play the playlist;
   expect B first. If an expected editing control is missing, report that too.
4. Create another playlist with the same name. Expect a distinct numbered name;
   the first playlist must keep its songs.
5. Rename one to `.Road Trip`. Expect a visible, non-hidden name (Road Trip or a
   numbered variant), without replacing an existing playlist.
6. Quit and reopen the app. Expect both playlists, their names and track order
   to persist.
7. Remove a song from the disposable playlist. Expect it to remain in Songs.
   Delete only the disposable playlist; expect the music files to remain.

## 4. Browse and background behavior

1. Search for part of a title, artist and album; expect matching results. Search
   nonsense; expect a helpful empty state. Clear it; expect the library back.
2. Check Artists and Albums. Expect correct grouping and album track-number order.
3. Start playback, go Home, and lock the phone for 30 seconds. Expect playback
   to continue. Check lock-screen title/artwork, play/pause and next/previous.
4. With downloaded tracks, enable airplane mode briefly. Expect local playback
   to work; restore your normal connectivity afterward.
5. Disconnect headphones while playing; expect playback to pause. Reconnect and
   resume. If a call/interruption occurs, verify playback does not unexpectedly
   start afterward when it had already been paused.

## 5. iCloud round trip — Mac and physical iPhone

1. On both devices, confirm the same Apple account and the app's music folder.
2. Add a uniquely named test copy on Mac. Expect it to arrive on iPhone after
   sync/download; play it. Do not treat a short network delay as a failure.
3. Create a disposable playlist on one device and inspect it on the other.
   Change its order/name and check the change propagates without duplicates.
4. Leave an album/detail screen open while adding another test track on Mac.
   Expect the phone's library/details to update after sync.
5. Optional deletion check: delete only the uniquely named test copy. Expect it
   to disappear after sync on both devices. Never use an original for this step.

## Report a failure

For the deletion work included in build 7, use the separate
[deletion acceptance checklist](DELETION-ACCEPTANCE.md). Only run its destructive
steps with disposable fixture copies in an isolated library.

Send: test section/step, app build, iOS version, expected result, actual result,
whether repeatable, and a screenshot/screen recording. For import failures,
include the file's source and whether it was selectable. Stop if any step appears
to affect real music unexpectedly.
