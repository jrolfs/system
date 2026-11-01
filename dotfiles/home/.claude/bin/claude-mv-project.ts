#!/usr/bin/env bun
/**
 * Re-key a Claude Code project store from one working directory to another.
 *
 * Claude Code keys everything by absolute path: sessions live in
 * `~/.claude/projects/<slug>/` where the slug is the munged working directory,
 * and the transcripts embed that directory throughout. Moving or renaming a
 * project directory therefore strands its threads: `/resume` in the new
 * location sees nothing, and the old location may no longer exist (the legacy
 * homeshick castle becoming `~/.config/system`, a worktree adopting a new
 * convention).
 *
 * This renames the store and rewrites embedded paths, in both plain
 * (`/Users/me/old`) and slug (`-Users-me-old`) forms. Replacement is
 * boundary-aware so a project whose path extends another's (`repo` vs
 * `repo.flake`) is never rewritten by the shorter one's move. claude-sync
 * propagates the move on the next push as a delete + add.
 *
 * When the destination already has a store of its own, because another machine
 * has been working in the new location, `--merge` moves the transcripts into it
 * instead of renaming. Session filenames are uuids, so the two sets coexist and
 * a collision means the same session is already there.
 *
 * `--session` re-keys named sessions rather than the store, for the case where
 * one thread moves and the rest stay: work that starts in a main checkout and
 * continues in a worktree cut for it. The store a thread leaves keeps
 * everything else it held. Zed's own record of a thread points at the old
 * directory and is Zed's to fix, which `claude-zed-sync move` does in the same
 * step.
 *
 * Do not re-key a project with a live session; finish or stop it first, and on
 * multi-machine setups run this only once the machine still writing the old key
 * has stopped (its pushes would resurrect it).
 */
import { existsSync, mkdirSync, readdirSync, renameSync, rmdirSync } from "node:fs";
import { join, resolve } from "node:path";
import * as z from "zod";

import { fail, flag, parse, repeatable } from "./lib/cli.ts";
import { replacementFor, rewritePaths, slugFor, storeFor } from "./lib/store.ts";

const USAGE = "usage: claude-mv-project [-n] [--merge] [--session ID] OLD NEW";

interface SessionMatch {
  /** Session ids matched, for counting what moved. */
  readonly sessions: readonly string[];
  /** Everything on disk belonging to them. */
  readonly names: readonly string[];
  readonly unresolved: readonly string[];
}

/**
 * Match session ids, or the leading part of one, to what the store holds for
 * them.
 *
 * A session is a `<id>.jsonl` and, when it offloaded anything, an `<id>/`
 * beside it holding tool results. Moving one without the other leaves the
 * transcript pointing at results that aren't there. Prefixes are accepted
 * because the listings you pick a session out of, Zed's and
 * `claude-zed-threads`, both abbreviate the uuid.
 */
const resolveSessions = (store: string, wanted: readonly string[]): SessionMatch => {
  const entries = readdirSync(store);
  const ids = [...new Set(entries.map((name) => name.replace(/\.jsonl$/, "")))];
  const matched = wanted.map((want) => ({
    want,
    ids: ids.filter((id) => id.startsWith(want)),
  }));
  const resolved = matched.filter(({ ids: found }) => found.length === 1).map(({ ids: found }) => found[0]!);
  return {
    sessions: resolved,
    names: resolved.flatMap((id) =>
      [`${id}.jsonl`, id].filter((name) => entries.includes(name)),
    ),
    unresolved: matched
      .filter(({ ids: found }) => found.length !== 1)
      .map(({ want, ids: found }) =>
        found.length ? `${want} matches ${found.length} sessions` : `nothing for ${want} in the store`,
      ),
  };
};

const main = (): number => {
  const argv = process.argv.slice(2);
  if (argv.includes("-h") || argv.includes("--help")) {
    console.log(USAGE);
    return 0;
  }

  const args = parse({
    argv,
    usage: USAGE,
    options: {
      "dry-run": { type: "boolean", short: "n" },
      merge: { type: "boolean" },
      session: { type: "string", multiple: true },
    },
    schema: z.object({
      "dry-run": flag,
      merge: flag,
      session: repeatable,
      positionals: z
        .array(z.string())
        .length(2, "needs the old directory and the new one, in that order"),
    }),
  });

  const [old, next] = args.positionals.map((path) => resolve(path)) as [string, string];
  if (old === next) return fail("old and new are the same directory");

  const oldStore = storeFor(old);
  const newStore = storeFor(next);
  if (!existsSync(oldStore)) return fail(`no project store at ${oldStore}`);

  const selected = args.session.length ? resolveSessions(oldStore, args.session) : undefined;
  if (selected?.unresolved.length) return fail(selected.unresolved.join("\n"));
  const names = selected ? selected.names : readdirSync(oldStore).sort();

  const existing = existsSync(newStore);
  // Taking over a store another machine is already writing to deserves a
  // deliberate --merge. Handing that store individual sessions does not, since
  // it keeps everything it held either way.
  if (existing && !args.merge && !selected) {
    return fail(`${newStore} already exists; pass --merge to move into it`);
  }

  // Checked before anything moves, so a refusal leaves both stores as they were
  // rather than half-moved.
  const collisions = existing
    ? names.filter((name) => readdirSync(newStore).includes(name)).sort()
    : [];
  if (collisions.length) {
    return fail(
      `${collisions.length} name(s) exist in both stores, starting with ` +
        `${collisions[0]}; resolve by hand`,
    );
  }

  const replacements = [
    replacementFor(old, next),
    replacementFor(slugFor(old), slugFor(next)),
  ];
  const what = selected
    ? `${selected.sessions.length} session(s)`
    : `${names.length} entr${names.length === 1 ? "y" : "ies"}`;

  if (args["dry-run"]) {
    const changed = names.reduce(
      (total, name) =>
        total + rewritePaths(join(oldStore, name), replacements, { dryRun: true }),
      0,
    );
    console.log(`would move ${what}\n  from ${oldStore}\n    to ${newStore}`);
    console.log(`would rewrite paths in ${changed} file(s)`);
    return 0;
  }

  mkdirSync(newStore, { recursive: true });
  const changed = names.reduce((total, name) => {
    const destination = join(newStore, name);
    renameSync(join(oldStore, name), destination);
    return total + rewritePaths(destination, replacements);
  }, 0);

  // The store itself only goes when everything in it left.
  if (!readdirSync(oldStore).length) rmdirSync(oldStore);

  console.log(`moved ${what}\n  from ${oldStore}\n    to ${newStore}`);
  console.log(`rewrote paths in ${changed} file(s)`);
  console.log(`threads now list under: cd ${next} && claude --resume`);
  return 0;
};

process.exit(main());
