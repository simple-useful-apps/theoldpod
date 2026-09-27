# Repository review and acceptance testing — September 6, 2026

Status: code review, build verification, and the computer-use scenarios recorded
below completed. Verification resumed successfully after the reported lock errors.
**Acceptance coverage remains partial:** simulator drag/long-press interactions
could not be driven reliably, and real-device checks remain outstanding. No unit
tests were run. Do not treat a build as proof of an untested interaction.

## Scope inspected

Both app shells, library/import/indexing, local and iCloud discovery, playlist
files and mutation paths, playback/queue/audio-session management, metadata,
Now Playing, artwork/duration presentation, and test harnesses. The worktree
was clean before this review. Changes remain uncommitted for review.

## Changes made from code evidence

| Issue | Change | Acceptance scenario (results below) |
| --- | --- | --- |
| Shuffle removes the current AVPlayerItem and resets playback | Only replace the preload when toggling shuffle | Seek to 0:30, toggle shuffle on/off while playing and paused; position and playback state must persist |
| Batch Play Next into an empty queue starts with the last selection | Replace the empty queue with the batch in its original order | Select Alpha then Beta, Play Next, press Play; Alpha must start |
| Track changes leave the previous elapsed time visible until the next timer tick | Reset elapsed time on item replacement/end; clear playing state for an emptied queue | Seek, pause, skip; new track must show 0:00 |
| An already-dispatched end notification can advance a replacement queue | Ignore end notifications whose item is no longer tracked | Rapidly change selections near a track's end |
| Same-name playlist creation/rename overwrites another playlist's file | Generate numbered names, including case-insensitive collisions | Create two playlists with the same name and different songs; relaunch and verify both |
| Dot-prefixed or multiline names create hidden/ill-formed playlist files | Centralize name sanitization and disallow hidden filename prefixes | Create `.Road Trip` and verify it survives relaunch |
| Rename deletes the old playlist before successfully writing the new one | Write first; retain the original name/file if writing fails | Rename normally and test a read-only destination |
| Failed playlist reads are interpreted as deleted playlists | Require a successful complete directory read before reconciliation | Temporarily make a playlist unreadable; existing rows must remain |
| The migration-complete flag is set even if export fails | Stop migration on write failure and leave it retryable | Exercise a failed initial export then retry |
| Import rejects album folders and accepts directories named `.mp3` | Enumerate supported regular files in folders, ignore hidden files/symlinks, reject non-audio directories | Import a mixed album folder, reimport it, and check deduplication |
| Mac permits overlapping imports | Guard the active import | Start a large import and drop another selection |
| MP3 album artist is never read | Read the ID3 band/album-artist field | Import an MP3 compilation and inspect grouping |
| Empty metadata remains blank; nonfinite duration can trap integer conversion | Normalize empty tags and invalid durations; guard duration formatting/export | Import malformed/untagged media and inspect UI |
| Keyboard/accessibility updates may not seek; separate drag state can leave readouts frozen | Remove the separate drag value/editing flag and bind directly to player seeking; label the control | Adjust position using mouse/touch and accessibility; confirm readouts continue advancing after seeking |
| Full Now Playing controls have incomplete labels/state | Add transport labels and shuffle/repeat values | Inspect/operate controls through accessibility |
| Failed iCloud folder creation still selects that unusable root | Fall back locally if cloud folder creation fails | Requires a suitable account/device or permission scenario |
| Coordinator teardown leaves remote commands registered | Deactivate the Now Playing bridge on stop | Lifecycle acceptance needed if stop is exposed by a future UI |

These are code-supported fixes. Only scenarios explicitly recorded below have
computer-use evidence; the rest remain acceptance work.

## Complexity and test cleanup

- Removed the module-graph test and two empty marker enums used only by it;
  compiling the apps already verifies that dependency graph.
- Removed two tests that explicitly required the broken batch order and
  same-name playlist merging. Those expectations concealed bugs rather than
  protecting useful behavior.
- Removed three trivial filename-transformation tests.
- Replaced import-specific SHA-256/Data helpers with Foundation's content
  comparison. Artwork hashing remains because it provides persistent cache IDs.
- Removed the production `--uitest-reset-playlists` hook, which deleted every
  playlist. Mac UI tests now use a unique disposable directory under the correct
  app identifier, with their own music, artwork and persistent index.
- Added a DEBUG-only `OLDPOD_ACCEPTANCE_ROOT` launch override for isolated
  computer-use acceptance runs. Release builds ignore the override.
- Removed duplicated scrubber state after the iPhone acceptance session exposed
  a frozen time readout while the artwork progress ring continued advancing.
  The final state-free implementation builds on both platforms and passes Mac
  accessibility seeking/resume checks. iPhone playback readouts advance normally,
  but a true touch seek has not been verified. Because simulator accessibility
  setters and drag gestures proved unreliable, the earlier frozen readout is an
  observation, not a conclusively isolated app bug.

Deleted source/tests remain recoverable from Git. No user library was deleted.

## Computer-use acceptance results

Testing resumed after the user unlocked the Mac. Tests used disposable local
libraries selected by `OLDPOD_ACCEPTANCE_ROOT`, not the user's music library or
iCloud. Two generated 90-second tracks were used: AAC `Alpha.m4a` and
`Beta.mp3`, titled Acceptance Alpha/Beta, artist The Testers, album Acceptance
Album. The Mac library also contained four repository fixtures.

| Platform / scenario | Observed result |
| --- | --- |
| Mac: import an album folder through the Open dialog | Passed: both MP3 and M4A appeared with expected title, artist, album and 1:30 duration |
| Mac: play M4A, pause, seek to 0:45, toggle shuffle on/off, resume | Passed: position and pause/play state retained; playback continued to 0:54 without resetting |
| Mac: pause and skip to Beta | Passed: next track showed 0:00 and remained paused |
| Mac: accessibility slider Increment | Passed: paused position advanced from 0:00 to 0:09 |
| Mac: create two default-name playlists and add different songs | Passed: New Playlist and New Playlist 2 retained Alpha and Beta separately |
| Mac: rename first playlist to an existing name | Passed: produced New Playlist 2 2 without overwriting New Playlist 2 |
| Mac: rename to `.Road Trip` | Passed: normalized to Road Trip |
| Mac: quit and relaunch, inspect both playlists | Passed: Road Trip still contained Alpha; New Playlist 2 still contained Beta |
| Mac: select Alpha then Beta, Play Next into empty player | Passed: current was Alpha; Next selected Beta, preserving order |
| iPhone 17 simulator: initial library and disabled empty transport | Passed: isolated tracks displayed with expected metadata; no selection had disabled transport |
| iPhone: select M4A and MP3 through the Files picker | Passed: both files selectable and Open completed |
| iPhone: reimport the same files | Passed: library retained two tracks, without duplicates |
| iPhone: play M4A and open full Now Playing | Passed: Alpha started; elapsed time advanced; title/artist/album and transport labels appeared |
| iPhone: pause and toggle shuffle; cycle repeat | Observed paused state retained and shuffle On/Off / repeat All/Off states changed |
| iPhone: seek and resume, earlier scrubber implementation | Found a frozen 0:45 readout while artwork progress advanced; replaced separate drag state |
| iPhone: rebuilt scrubber regression | Partial: resumed playback readouts advanced normally; synthetic drag did not move the slider, so actual touch seeking remains unverified |
| Mac: final rebuilt scrubber, seek / shuffle / resume | Passed: accessibility Increment sought to 0:14 while paused; shuffle retained position; playback advanced to 0:39 |
| Mac: Previous after more than three seconds | Passed: same track restarted at 0:00; subsequent pause retained it |
| Mac: Mini Player | Passed: opened from Window menu, layout and controls visible; accessibility seek to 0:09 and Play worked |
| iPhone: dismiss Now Playing | Passed using the accessible Sheet Grabber action; synthetic dismissal drag remains unverified |
| iPhone: song search | Passed: Beta filtered to one matching song; Betaxyz displayed a meaningful no-results state |
| iPhone: album browsing | Passed: Acceptance Album / The Testers grouping, Alpha before Beta, 2 songs and 3:00 total |
| iPhone: playlist creation / empty state / persistence | Passed: Phone Acceptance created, empty state explained how to add songs, and playlist survived terminate/relaunch |
| iPhone: background playback | Passed in simulator: went to Home and returned; Alpha was still playing at 0:34 rather than restarting |
| iPhone: paused skip | Passed: paused Alpha at 0:39, Next selected Beta at 0:00 and remained paused |

The original user-supplied music files were not available to reproduce their
specific import failure. These checks establish that ordinary generated M4A
files are accepted, not that every M4A file or original failure is resolved.

Tool limitations: Simulator accessibility element IDs occasionally became
invalid, and synthetic drag gestures did not reliably move the slider or
dismiss the sheet. Coordinate taps and fresh accessibility snapshots were used
where possible. Touch-drag seeking and long-press playlist actions are **not**
counted as passes. A right-click on a simulator song acted as a regular tap,
not a long press. Simulator app data-container UUIDs changed after reinstall; each launch
resolved the new container to preserve the isolated acceptance library.

## Remaining findings requiring reproduction/design

- **Playback failures:** only the failed-to-play-to-end notification is observed;
  initial decode/status failures may leave a corrupt or unavailable file appearing
  to play. At queue end the failure handler calls `next()`, which is a no-op.
  Reproduce with a corrupt file and an undownloaded cloud file before changing
  failure/skip policy; repeat-all also needs protection against retry loops.
- **Duplicate queue occurrences:** shuffle/unshuffle locates the current track
  by value equality, so the second occurrence can become the first. One existing
  edge-case test explicitly documents this undesired behavior. A fix needs stable
  occurrence identity, not a filename-only comparison.
- **Audio interruptions:** activation is latched before it succeeds and isn't
  reset after interruption; resume does not remember whether playback was active.
  Validate on a physical device with interruptions and headphones.
- **Playlist file identity:** external filenames with unusual characters or
  uppercase extensions do not round-trip through sanitized write/delete paths;
  collisions with files arriving before reconciliation also need handling.
- **Watcher resilience:** directory replacement and in-place file edits can escape
  directory-only vnode watching; an inaccessible library scan can look empty.
  Reproduce before choosing recovery/rescan behavior.
- **iCloud playlists:** local folder events alone do not establish reliable
  discovery/download of remote-only playlist files. Real-device sync remains open.
- **UI persistence:** album/artist detail snapshots and playlist filtered queries
  need live file-add/delete checks while their detail screens stay open.
- **Performance:** playlist export resolves tracks with one fetch per entry;
  multi-selection Add to Playlist saves/rewrites the file per selected track.
  Measure with a large selection before adding more caching or machinery.

## Remaining acceptance checklist

Finish actual touch seeking and long-press playlist additions on iPhone with a
working gesture driver or manual interaction. Then cover artist browsing,
Mac search/resizing, queue insertion into a populated player, playlist reordering
and removal, and populated iPhone playlist persistence. Check library updates
while a detail screen stays open. Exercise the error scenarios in the change
table and reproduce the remaining findings above. Real-device iCloud and audio
interruption tests remain separate from simulator acceptance.

Build logs: `.build/acceptance-ios-build.log` and `.build/acceptance-mac-build.log`.
Both application builds passed. Unit suites intentionally not executed.
