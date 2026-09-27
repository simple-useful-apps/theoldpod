# Exploratory pass — September 26, 2026

Both apps were driven against a throwaway library of 40 synthetic files
(two-disc album, a compilation, shared album titles, accents/CJK/emoji,
very long names, missing tags, a 0-byte and a random-bytes `.mp3`, a
70-minute track, three audiobooks, a playlist with a missing file). The Mac
app ran from `OLDPOD_ACCEPTANCE_ROOT`; the iPhone 17 Pro simulator ran the
same library. Real music and the iCloud folder were never opened.

## Fixed in this branch

1. **Unplayable file hangs playback (both).** Tapping a 0-byte or corrupt
   `.mp3` showed Pause at 0:00 forever and never moved on. Now it skips to the
   next track, or stops cleanly if it was the last one.
2. **iPhone Songs order.** Lowercase titles ("corrupt", "lowercase title")
   sorted after Z. Now case- and accent-insensitive, matching the Mac.
3. **Artist order ignores accents (both).** "Émile & the Ümlauts" sorted after
   "The Zebras"; it now files under E.
4. **Non-square artwork (both).** A 3:2 cover spilled out of its square
   thumbnail into the song title.
5. **Mac Albums/Artists song table with nothing selected.** Tracks were
   interleaved across albums (every track 1, then every track 2 ...). Albums
   now stay together, even two albums both titled "Greatest Hits".
6. **Mac Songs search ignores accents** ("bjork" finds Björk), like every
   other search in both apps already did.
7. **Mac Time column** truncated "1:10:00" to "1:10:…".

Added after the Mac click-and-keyboard pass:

8. **Mac playing icon vanished in a selected row.** The blue speaker glyph
   was drawn on the blue selection highlight.
9. **Mac book page ran flush against the sidebar.** "Listen", "Chapters" and
   the chapter rows had no leading margin.

## Usability suggestions to go over

Rough priority order. All except #2 were implemented on September 27 at
Matt's request (#9 as "list track artists too": compilation artists appear
under their own names as well as under Various Artists). #2 (hiding junk
files) remains open.

### Playback

1. **Tell me when a file can't play.** Skipping a broken file is now correct
   but silent. A brief "Couldn't play 'empty'" note (or a warning glyph on the
   row) would explain the jump.
2. **Hide or flag junk files.** A 0-byte `empty.mp3` and a garbage
   `corrupt.mp3` both appear as songs (0:00 and a made-up 0:17). Consider
   skipping zero-duration/unreadable files at import, or marking them.
3. **Mac: Play with nothing playing should play the selection.** Selecting a
   song and pressing Play/Pause (or Space) does nothing until something has
   been double-clicked; the Play button is disabled. iTunes played the
   selection, or the list from the top.
4. **Mac: missing classic shortcuts.** Go to Current Song (⌘L), volume up/down
   (⌘↑/⌘↓), and a Playback-menu Skip Back/Forward 15s for books.
5. **Use album art for tracks without their own.** "AAC Tone" is on the
   illustrated "First Light" album but shows a blank note in Now Playing and
   the mini player.
6. **Now Playing (iPhone) has no volume slider, AirPlay/route button, or
   Up Next.** The bottom third of the sheet is empty.
7. **Books: hide Shuffle and Repeat** in Now Playing; shuffling chapters is
   never wanted. The 15-second skips and speed control are small and
   low-contrast next to the main transport.

### Browsing

8. **Disc headers on multi-disc albums.** "First Light" lists tracks
   1 2 3 4 1 2 3 4 with no Disc 1 / Disc 2 separation (iPhone). The Mac album
   table shows no track numbers at all; a narrow "#" column would help.
9. **Compilation artists are invisible in Artists.** Björk, Sigur Rós, AC/DC
   only exist under "Various Artists". iTunes listed track artists too (or
   offered a Compilations toggle). Worth a decision either way.
10. **Put "Unknown Artist" / "Unknown Album" last** instead of alphabetically
    in the middle of the list.
11. **Cap long titles at two lines on iPhone.** A very long title wrapped to
    five lines plus two for the artist, making one row a third of the screen.
12. **Playlists are listed by creation date.** Alphabetical (as in the Mac
    sidebar habit from iTunes) is easier to scan once there are more than a
    few.
13. **Book rows show a generic book icon and no author** even when the files
    have cover art and an author tag. The book page's "Listen" row doesn't
    look tappable, and there's no progress or total time on the page.
14. **Playlist song count includes missing files.** "Road Trip — 3 songs ·
    0:35" when one of the three is missing. Consider "2 songs, 1 missing".

### Mac app shell

15. **Add a File > Add to Library… (⌘O)** menu item. Importing is only the
    toolbar "+" today, and there is no File menu.
16. **Mini Player is 340×400 of mostly artwork.** iTunes' mini player was a
    thin strip with title and transport. A compact layout, and an optional
    "Keep on top", would make it more useful.
17. **Status line for the library** (e.g. "40 songs, 3.1 hours") at the foot
    of the song table, as iTunes had.
18. **Setup failure screen is a dead end.** "The Old Pod couldn't set up its
    library folder." offers no reason, retry, or Show in Finder.
19. **Show in Finder** in the song context menu. For a files-first app it is
    the natural way to get from a song to its file.
20. **Get Info shows only editable tags.** No artwork, file path, format,
    bitrate, size or duration, and track/disc have no "of N" totals.
21. **Mark the playing chapter on a book page,** as the song table does. Also,
    starting a book inserts a Resume row that pushes the chapter list down,
    so a second click can land on the wrong chapter.
22. **Scrubber shifts sideways** when the elapsed time grows a digit
    (9:59 → 10:00). Fixed-width time labels would keep it still.

## Mac click-and-keyboard pass (checked, working)

Double-click to play, Space to pause/resume, ⌘→ to skip, dragging the
scrubber on a 70-minute track, the song context menu, Get Info editing a
title (the file and an open playlist both picked up the new name), the
Delete confirmation (cancelled, nothing deleted), a broken file skipping to
the next song, Books Listen/Resume with the 15-second skips and speed menu,
and reopening the window after closing it. A normal quit and relaunch
reopened the window, so the earlier "launched with no window" came from
force-quitting the test app and is not listed as a problem.

## Not covered

- Dark mode, VoiceOver, Dynamic Type, and real iCloud sync.
- The UI test suites were not rerun for this pass; package tests pass.
- Edge case left alone: with Repeat All on and a queue of only broken files,
  playback may cycle through failures rather than stopping.
