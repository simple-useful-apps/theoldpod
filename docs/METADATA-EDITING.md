# Mac music metadata editing

The Mac app can edit title, artist, album, album artist, genre, year, track,
and disc for one downloaded MP3 or M4A music file at a time. Select a song and
choose **Library > Get Info**, press Command-I, or use the row's Get Info menu.
Audiobook chapters, cloud placeholders, batch changes, and artwork editing are
intentionally out of scope.

The app stream-copies the audio through its bundled minimal FFmpeg helper, so
editing tags does not re-encode it. Before replacing the source, it verifies
playability, duration, audio codec/sample rate/channel count, the requested
ordinary tags, and embedded artwork. It also checks that the original has not
changed since editing began, then performs a coordinated same-folder replace.

FFmpeg carries other container metadata forward on a best-effort basis, but
private or opaque ID3 frames and MP4 atoms are not fully inventoried by the
app and cannot be guaranteed. Keep an original when working with files that
contain application-specific tags.

## Manual acceptance

Use disposable copies of one tagged MP3 and one tagged M4A.

1. Select exactly one downloaded music track and open Get Info from each of
   the three entry points. Confirm the Library command is disabled for no
   selection, multiple selection, an unavailable cloud file, and book chapters.
2. Change all eight fields and save. Confirm Songs, Artists, Albums, playlists,
   player bar, and queue labels refresh without restarting a playing item.
3. Reopen Get Info and confirm the values were read from the file. Clear title,
   artist, and album; after saving, title should fall back to the filename and
   artist/album should display as Unknown. Quit and relaunch to prove the tags
   are embedded rather than stored only in the index.
4. Confirm duration, audible playback, audio characteristics, and artwork are
   unchanged. Saving without changes must not modify the file.
   When changing track or disc number, an existing total must remain intact
   (for example, track `4/4` changed to `2` is stored as `2/4`). Clearing the
   number clears the complete number/total tag; reopen Get Info and inspect the
   file to confirm the old total was not retained by itself.
5. Change the source externally while Get Info is open. Saving must refuse to
   overwrite the newer version.

## Acceptance results — September 19, 2026

Computer-use acceptance passed against disposable MP3 and M4A copies in an
isolated Mac library:

- Get Info from the song table, Library > Get Info / Command-I, and a playlist.
- All eight fields save, refresh immediately, reopen correctly, and persist
  across app restart. Multiple selection correctly disables Get Info.
- Clearing tags produces the filename, Unknown Artist, and Unknown Album
  fallbacks. Clearing Track or Disc removes its total too.
- Track/disc totals survive number changes (`1/1` to `7/1`, `4/4` to `2/4`,
  and disc `2/3`). Ordinary comments also survive subsequent edits.
- Compressed audio hashes stayed identical for both formats and the MP3 artwork
  hash stayed identical. Playback continued from 0:10 to 0:22 while the current
  song was edited; typing a space in a field did not pause it.
- An external edit made while the sheet was open was rejected without being
  overwritten. Cancel, no-op save, invalid-number feedback, and temporary-file
  cleanup passed.

Both Mac and iOS builds, SwiftFormat, and `git diff --check` passed. No unit
suite was run. Physical iCloud propagation, cloud eviction during editing,
Intel runtime behavior, forced replacement failure, and preservation of
undisclosed private/opaque metadata remain unverified.
