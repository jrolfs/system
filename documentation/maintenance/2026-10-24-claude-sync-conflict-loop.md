# claude-sync conflict loop

**Hosts:** ala, adrian · **Fixed in:** `7dc81ab` (claude-sync 1.17.2 with two
patches)

## Summary

ala saw only occasional use for about a month while adrian did most of the
work. Back on ala full time, every pull saved `.conflict` copies of the same files again, until there were 791
copies of 29 files. One push from ala then uploaded ala's older versions of
those files over adrian's newer ones, along with 348 of the copies. Nothing was
lost: adrian's versions survived in ala's copies and on adrian's disk. Both
sides were merged by hand, and claude-sync is now patched so the loop can't
recur.

## Timeline

- **2026-09-18 to 10-18:** the occasional session on ala leaves a few copies at
  a time, 139 in all.
- **2026-10-24:** ala back in daily use. Each session start runs
  `claude-sync pull` from the SessionStart hook, as does `wt restore`, and each
  pull adds about 28 copies, 652 that day.
- **22:57:** a Stop hook push from ala uploads ala's versions of the conflicted
  files over adrian's, and most of the 348 copies that ended up in the bucket.
- **23:30–00:10:** backups taken, upstream checked, patched claude-sync built,
  files merged on ala, both machines cleaned up and verified.

## Root causes

1. **A conflict is never recorded as handled.** When a pull finds a file changed
   on both sides, `handleConflict` saves the remote copy as
   `<file>.conflict.<timestamp>` but leaves the original's state untouched. The
   next pull sees the same "both changed" condition and saves another copy, every
   time.
2. **That stale state made push upload old versions.** The state still held the
   hash from before the conflict, so push saw ala's file as a local edit and
   uploaded it over adrian's newer copy. Upstream tracks the general version of
   this as #70.
3. **Append-only transcripts counted as conflicts.** A session transcript that
   one machine had simply extended was treated as a two-sided conflict (#69).
   `history.jsonl` is last-writer-wins (#72). Both made conflicts far more
   common than real divergence.
4. **`.conflict` copies were synced like any other file,** so one machine's
   copies spread to every machine.
5. **Pulls are frequent.** The SessionStart hook and `wt restore` both pull, so
   the loop ran on every session start.

## What we did

- **Backed up.** ala: `~/.claude-sync/backup-20261024/` holds `state.json` plus
  every conflicted file and copy (about 520 MB). adrian:
  `~/.claude-sync/conflicts-adrian.tar.gz` and `state-adrian-20261025.json`.
- **Patched claude-sync** (`7dc81ab`, `overlays/claude-sync/`):
  - The flake input moved to upstream 1.17.2.
  - `pr-77-multi-machine-sync.patch` is tawanorg/claude-sync#77 merged onto
    1.17.2. It fast-forwards or union-merges transcripts instead of declaring
    conflicts, union-merges `history.jsonl`, and stops syncing `.conflict` and
    `.lock` files. Copies already tracked get pruned from the bucket on the next
    push.
  - `conflict-copy-loop.patch` is ours, covering files #77 doesn't. When both
    sides changed to identical content, the file is marked resolved. A copy
    identical to the newest one already saved isn't written again. Its tests fail
    without the patch.
- **Merged the affected files on ala** so each held both machines' content:
  - Transcripts: adrian's copy, plus any of ala's lines it lacked, deduplicated
    by `uuid`. Claude Code rebuilds the thread from `parentUuid`, so a transcript
    holding both branches of a fork still resumes.
  - `history.jsonl`: the union of every copy, sorted by timestamp.
  - `MEMORY.md` files and `.zed-threads/adrian.json`: adrian's copy, which was
    newer.
- **Cleaned up both machines.** Deleted ala's 791 local copies and pushed with
  the patched binary, which removed the copies from the bucket. On adrian:
  switched, folded its 6 old copies into the live files (they held nothing new),
  deleted them, pulled, pushed. `claude-sync diff` on both then showed 0
  remote-only and 0 modified files.

## Still to do

- **Drop `pr-77-multi-machine-sync.patch`** once #77 lands upstream. The
  maintainer has chosen to land it first (#91) but hadn't reviewed it as of
  2026-10-24. Both patches are diffs against 1.17.2, so any bump of the input
  means regenerating or dropping them.
- **Send `conflict-copy-loop.patch` upstream** once #77 has landed, since it
  builds on #77's helpers.
- **Delete the backups** once nothing turns out to be missing.
- **irulan** runs claude-sync too. Switch it before its next Claude session.
- **Non-transcript files** (`MEMORY.md`, `custom-title.json`, Zed thread
  indexes) still get one `.conflict` copy on a real conflict. Merge those by
  hand.

## Next time

Coming back to a machine that hasn't been used in a while:

1. `nix-switch --pull` before opening Claude, so the SessionStart pull runs
   whatever version is current.
2. `claude-sync status` and `find ~/.claude -name '*.conflict.*'`. If copies
   show up, stop and work out why before pushing.
3. Never `claude-sync conflicts --keep remote`. It processes copies newest
   first and renames each over the original, so the file ends up holding the
   oldest one. `--keep local` is safe.
4. `claude-sync diff` is the quickest check that a machine and the bucket agree.
