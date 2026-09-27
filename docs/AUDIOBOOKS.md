# Audiobooks

Version 1.0, build 5 uploaded successfully to App Store Connect on September 7,
2026. Apple reported the package was processing; TestFlight availability after
processing has not yet been confirmed.

## Use

1. Open **Books → Import Book** on iPhone or Mac.
2. Enter a book title, then select the downloaded folder or all its chapters.
3. Open the book and choose **Listen / Resume**. Tapping an individual chapter
   intentionally starts that chapter at zero.
4. Tap the mini-player title on iPhone for speed (0.75×–2×) and 15-second controls.
   Chapter previous/next remains available in full Now Playing. On Mac, book
   speed/skip controls appear in the player bar and Mini Player.

Original downloads are not modified. Copies live under
`<library folder>/Audiobooks/<book title>/`. These folders define book identity,
so untagged chapters don't mix with other books or appear in Songs/Albums/Artists.
Chapter filenames are naturally sorted: numbered Manning downloads keep their
order. A repeated book title gets a numbered folder instead of overwriting an
existing book. Reimporting a whole book currently creates another book copy.
Files previously imported as music are not automatically moved/reclassified.

## Resume behavior

- Each book keeps its own chapter, position, and speed, even after playing music
  or another book. Relaunch restores the last queue **paused**.
- Progress is atomically saved every two seconds during playback and immediately
  on pause, seek, speed change, track change, and app background/quit events.
  An abrupt crash can lose approximately the last two seconds.
- Relative paths are saved, not absolute container URLs; rebuilding the index or
  updating the app can still resolve the chapter against the current library.
- Missing tracks are omitted from restored queues. Undownloaded/zero-duration
  chapters must become available before their saved position can be restored.
  Explicit Resume on unavailable media leaves the bookmark unchanged and tells
  you to retry after download.
- Book completion offers **Listen Again**. Skips clamp to the current chapter's
  boundaries; use chapter next/previous to cross them.
- Book files can sync through iCloud, but bookmarks are **device-local**. Renaming
  book folders/chapter files changes their identity; bookmarks are not migrated
  across manual renames. There is no bookmark cloud-sync or M4B support yet.

## Acceptance evidence — September 7, 2026

No unit tests run. Both app builds passed. Computer-use checks used isolated
local libraries, not the user's iCloud library:

- Mac: imported the supplied `negro2-audio` folder through Books → Import Book.
  One book displayed 23 ordered chapters and 13:05:58 total. Originals unchanged.
- Mac: chapter 1 played; paused forward/back moved 0:09 → 0:24 → 0:09.
- Mac: selected 1.5× without unpausing; resumed playback advanced normally.
- Mac: quit/relaunch restored chapter 1 paused at 0:21 and 1.5×.
- Mac: played music, returned to Books, and Resume returned to chapter 1 at
  0:21 / 1.5×. Songs still contained only music, not the imported book chapters.
- iPhone 17 simulator: imported a two-file MP3/M4A folder as Phone Book. Book
  displayed separately with two chapters and 3:00 total.
- iPhone: paused 15-second skips moved 0:33 → 0:48 → 0:33; speed menu selected 1.5×.
- iPhone: terminated, installed the updated build, relaunched, and observed the
  same chapter restored paused at 0:33 and 1.5×. The container UUID changed, and
  relative-path restoration still worked.
- iPhone: final plain Books/chapter lists and larger skip/speed touch targets
  inspected visually. Resume showed the saved chapter/time.

Physical lock-screen skip/rate commands, actual audio pitch/quality at each rate,
iCloud-only chapter downloads, interruptions, disk-full handling, completed-book
replay and abrupt-kill timing still need manual/device acceptance. No claim of
cross-device bookmark synchronization. Use build 5 or later; the earlier
TestFlight build 4 does **not** contain these audiobook features.
