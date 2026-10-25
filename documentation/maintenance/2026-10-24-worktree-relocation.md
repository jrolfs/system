# Worktree relocation on ala

**Hosts:** ala, after adrian · **Fixed in:** `ef16697`

## Summary

Worktrees of this repo moved from `~/.config/system.<branch>` siblings to
`~/.config/.system/<branch>`. adrian made the change and ran `wt relocate`
there. On ala the same command moved nothing, `wt restore --all` recreated
worktrees at the old paths, and worktrunk treated `master` as the default
branch. None of it was a problem with the relocation tooling on its own: ala's
clone was quietly out of step with the repository, and that hid the new
configuration. Fixing the clone and then relocating also turned up four bugs in
`wt-relocate` and `claude-mv-project`.

No work was lost. Every worktree adrian handed off already matched its newest
snapshot on disk, so only the locations were wrong.

## Timeline

- **adrian:** the move to `../.system/` landed, along with `wt relocate` and
  handoff and restore changes to go with it (everything after `0d6643a`).
  Relocated there, then `wt handoff --all`.
- **ala:** `wt relocate` reported nothing to move. `wt restore --all` restored
  the old-layout snapshots. `wt list` showed `master` as the default branch.
- **ala:** the remote and default branch were fixed by hand, stale snapshot refs
  deleted, and the 25 worktrees relocated. The first attempt passed every branch
  as one argument, moved nothing, and still renamed 9 snapshots backwards and
  pushed them. The successful run renamed them forward again.

## Root causes

1. **The remote still had the repository's old name.** `origin` pointed at
   `git@github.com:jrolfs/macos.git`. GitHub redirects that, so fetch and push
   kept working. But worktrunk identifies a project by its remote URL, so ala was
   `github.com/jrolfs/macos` and never matched
   `[projects."github.com/jrolfs/system"]`. The `../.system/` template only
   applies under that block, so ala used the default sibling template, and by
   that template every worktree was already where it belonged.
2. **The default branch was cached as `master`.** `refs/remotes/origin/HEAD`
   still pointed at `origin/master`, which no longer exists, and worktrunk had
   saved `worktrunk.default-branch master` in git config.
3. **Snapshot refs aren't pruned.** `wt-restore` fetches `refs/wip/*` but never
   prunes, so ala kept the old `system.<branch>` snapshots after adrian's
   relocate deleted them from origin. `restore --all` restored those. The new
   snapshots couldn't create their `.system/` paths, because each branch was
   already checked out at its old one.
4. **`wt-relocate` renamed snapshots after a relocate that moved nothing.** The
   snapshot step matched snapshots against wherever the worktrees were, so after
   a failed `wt step relocate` it moved snapshots back to the old paths and
   pushed that.
5. **Its preview listed snapshot renames backwards,** for the same reason.
6. **`git worktree move` doesn't create the destination's parent,** so a
   relocate into a new `~/.config/.system/` fails with "No such file or
   directory".
7. **Thread stores collided.** claude-sync had already pulled adrian's re-keyed
   threads into the new store paths. `claude-mv-project` refused to move into an
   existing store without `--merge`, and refused again on the shared session even
   with it.

## What we did

- Set `origin` to `git@github.com:jrolfs/system.git`, ran
  `git remote set-head origin --auto`, and unset `worktrunk.default-branch`.
- Deleted the local `refs/wip/system.*` refs once each was confirmed to be an
  ancestor of its replacement.
- Removed the `drop-lix-pin` worktree, since `main` already had its commit, and
  moved this session's thread to the main checkout with
  `claude-mv-project --session`.
- Relocated the 25 other worktrees. Moved the two old thread stores that
  duplicated adrian's into ala's Trash.
- `ef16697` fixed causes 4–7.
  - `wt-relocate` takes its plan from
    `wt step relocate --dry-run --format json` before doing anything.
  - The preview works from planned paths.
  - Snapshots of worktrees still waiting to move are left alone.
  - It creates destination directories.
  - It passes `--merge` to `claude-mv-project`, which now drops a session the
    destination already has at least as far along.

## Still to do

- **`migration-flake`** is a worktree at `~/.homesick/repos/macos.flake`, and a
  bare `wt relocate` would move it into `.system/`. If it should stay put,
  `git worktree lock` it.
- **`refs/wip/macos.flake`** exists only on ala, because adrian deleted it from
  origin. It's an old snapshot of that worktree and can go.
- **Any other machine with worktrees of this repo** needs the same checks before
  its first relocate. See below.
- **Snapshot pruning** belongs in `wt-restore` itself (cause 3), and it hasn't
  been added yet.

## Next time

Before relocating, restoring or handing off on a machine that hasn't been used
in a while:

1. `git remote -v` shows `github.com/jrolfs/system`. If not,
   `git remote set-url origin git@github.com:jrolfs/system.git`.
2. `git remote set-head origin --auto` and
   `git config --unset worktrunk.default-branch`. `wt list` should then show
   `main`.
3. `git fetch --prune origin '+refs/wip/*:refs/wip/*'` so restore only sees
   snapshots that still exist.
4. Close agent sessions running in any worktree that will move.
5. `wt relocate --preview`, then `wt relocate`, then `wt restore --all`.
   Relocating first means restore finds each branch where its snapshot expects.
