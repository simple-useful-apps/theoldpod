# Song and book deletion acceptance

Scope: confirmed removal of library songs and whole audiobook folders on iPhone and Mac. Do not delete original user media during acceptance. Use newly created copies of fixtures in an isolated library.

## Required behavior

- A named confirmation precedes any file change; Cancel leaves files, library entries, and playback unchanged.
- Deletion moves the exact selected library file or book folder to system Trash. No permanent-delete fallback is allowed.
- Shared iCloud library confirmations explain that other devices are affected. The app must not promise an unverified restoration location or retention period.
- Books are deleted as whole folders, without affecting neighboring books or regular songs.
- Deleting current or queued items cannot leave playback pointing at trashed files. Unrelated items should remain usable.
- Song deletion does not delete playlist files. Removing a song from a playlist remains distinct from deleting it from the library.
- Unsupported, outside-root, or symlink targets are rejected. Failures are visible, not reported as successful deletion.

## Computer-use checklist

1. Cancel a song deletion; verify its row and source file remain.
2. Confirm a song deletion; verify its row and source file disappear from the library, unrelated files remain, and a refresh/relaunch does not restore it.
3. Cancel then confirm a whole-book deletion; verify only that book folder and its chapter rows disappear.
4. On Mac, delete multiple selected songs; verify exactly the selected targets are affected.
5. Delete a currently playing fixture; verify the removed title is no longer current and playback is stopped or moves only to a valid remaining item.
6. Delete a queued fixture; verify the remaining queue does not include it and unrelated playback is preserved where possible.
7. Verify the confirmation's shared-library warning and failure feedback, using only safe test setups.

## Results

Baseline implementation built on both platforms and passed `git diff --check`.
Independent review identified root-redirection safety, inaccessible-versus-missing
classification, and post-deletion refresh failure reporting fixes. These are being
corrected before final acceptance.

On baseline Swift-source aggregate `0482c5de1ca1d2d2ecf515770a45a751839f2a4a7c5b24b00f6c03be6ab20000`:

- Mac song and book Cancel: passed, with all rows and test files remaining.
- iPhone named song/book confirmations and Cancel file safety: passed. Source files
  and the seed hashes remained unchanged.
- iPhone Cancel visible-list stability: failed; a row could temporarily disappear
  after invoking a destructive swipe action, despite files remaining. Pending fix
  and recheck.
- No destructive confirmation buttons have been clicked. The computer-use tool
  requested explicit user confirmation for the isolated Trash acceptance steps;
  that confirmation is pending.

Actual Trash success, queue cleanup after deletion, refresh/relaunch persistence,
multi-selection, partial failure, physical iCloud propagation, and recovery remain
unverified. Do not treat passing cancellation or a successful build as evidence of
successful file deletion.

Correction checkpoint `0b0ebb1cbf66cef0aeda34cead7ba2d552d8424b188dfaae34c35660718a3306`:

- Both platform builds passed. Review confirmed root identity protection and
  explicit missing-file classification, but requested a final correction so an
  unrelated buffered index batch cannot prematurely acknowledge deletion refresh.
- Mac song/book Cancel passed with all rows and files unchanged.
- iPhone swipe-to-confirm song/book Cancel now passed with all three songs and
  both books immediately visible; the earlier list disappearance did not recur.
- Device-only confirmation wording was verified on both platforms.
- All fixture files, companion notes, playlist, and original seed hashes remained
  intact. No actual Trash confirmation was clicked; user approval remains pending.

## Final code checkpoint — September 12, 2026

Product Swift aggregate:
`6b3cc6d3f8cfaa5b597952093d6ead0fa05650afc38e513106c65d5c41bd3b77`.
Both builds, formatting, and diff checks passed. Independent targeted review found
no remaining actionable findings. Deletion refresh now waits for a committed index
snapshot in which all successful song paths/book prefixes are absent; timeout and
save/read failures remain distinguishable from successful Trash operations.

Tester independently verified this hash and inspected readiness. The final delta
does not change the confirmation UI that passed cancellation checks at the prior
checkpoint. This is **not** complete deletion end-to-end acceptance.

Blocked pending explicit computer-use deletion approval:

- Actual song Trash and row/file disappearance on both platforms.
- Refresh/relaunch without resurrection.
- Whole-book Trash, companion-file scope, detail dismissal, and neighboring-book safety.
- Filtered Mac multi-selection targeting.
- Current and queued playback cleanup, including unshuffle behavior.
- Playlist preservation after actual song deletion.
- Empty Songs while Books remain.
- Visible partial-failure, unsafe-target, permission, and refresh-warning feedback.

Physical iCloud propagation and platform Trash recovery/retention are also
unverified. The isolated Mac test instance was quit. No real user media or fixture
seed files were deleted. This development change has not been uploaded to TestFlight.
