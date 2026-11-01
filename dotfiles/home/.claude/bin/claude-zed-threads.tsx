#!/usr/bin/env bun
/**
 * List Claude Code threads started by Zed's ACP client, with their home dirs.
 *
 * Zed drives Claude Code non-interactively over the Agent Client Protocol, so
 * the threads it starts land in the same per-project store as the terminal CLI
 * (`~/.claude/projects/<slug>/<id>.jsonl`) but with a different fingerprint:
 * the first JSONL record carries `operation: "enqueue"` and no `mode:
 * "normal"`, whereas interactive terminal sessions are `mode: "normal"` with no
 * `operation`.
 *
 * The built-in `/resume` picker mixes both together *and* is scoped to the
 * current project directory. Zed history is siloed per working directory, so
 * threads you started elsewhere never appear. This isolates the Zed/ACP threads
 * and can widen the scope to every worktree of the current repo (`--repo`) or
 * everything (`--all`).
 *
 * At a terminal the threads are a table sized to the window, with the title
 * taking whatever the fixed columns leave and the worktree column dropped
 * entirely when there is no room for it. Piped, the output is the older plain
 * form with a resume command under each thread, because that is what the
 * /resume-zed slash command reads.
 *
 * `--pick` opens the same table as a filterable picker and writes `id<TAB>cwd`
 * for the chosen thread to stdout, which is what lets the shell function
 * around it cd into the thread's directory before resuming: the picker draws
 * on stderr so stdout carries nothing but the answer. Ink and React only load
 * on that path, so listing stays as cheap as it was.
 *
 * Any scripted `claude -p` run is also non-interactive and will appear here; in
 * a repo working directory these are almost always Zed threads in practice.
 */
import { resolve } from "node:path";
import * as z from "zod";

import { fail, flag, parse } from "./lib/cli.ts";
import { cellsFor, columnsFor, printTable } from "./lib/thread-table.ts";
import {
  displayFor,
  resumeCommand,
  zedThreads,
  type Scope,
} from "./lib/threads.ts";

const USAGE = "usage: claude-zed-threads [-d DIR] [--repo | --all] [--sk | --pick]";

const main = async (): Promise<number> => {
  const argv = process.argv.slice(2);
  if (argv.includes("-h") || argv.includes("--help")) {
    console.log(USAGE);
    return 0;
  }

  const args = parse({
    argv,
    usage: USAGE,
    options: {
      dir: { type: "string", short: "d" },
      repo: { type: "boolean" },
      all: { type: "boolean" },
      sk: { type: "boolean" },
      pick: { type: "boolean" },
    },
    schema: z
      .object({
        dir: z.string().default(process.cwd()),
        repo: flag,
        all: flag,
        sk: flag,
        pick: flag,
        positionals: z.array(z.string()).max(0, "takes no positionals"),
      })
      .refine((value) => !(value.repo && value.all), "pass --repo or --all, not both")
      .refine((value) => !(value.sk && value.pick), "pass --sk or --pick, not both"),
  });

  const directory = resolve(args.dir);
  const scope: Scope = args.repo ? "repo" : args.all ? "all" : "here";
  const threads = zedThreads(directory, scope);
  // Only a widened scope can turn up threads from more than one directory, so
  // that is when a row has to say which one it came from.
  const multi = scope !== "here";

  if (args.sk) {
    threads.forEach((thread) =>
      console.log(`${thread.sessionId}\t${thread.cwd}\t${displayFor(thread, multi)}`),
    );
    return 0;
  }

  if (args.pick) {
    if (!process.stdin.isTTY) return fail("--pick needs a terminal on stdin");
    if (!threads.length) return fail(`no Zed/ACP threads found (${scope}: ${directory})`);

    // Imported here rather than at the top so listing doesn't pay for Ink.
    const { pick } = await import("./lib/picker.tsx");
    const chosen = await pick({
      heading: `zed threads · ${scope}`,
      columns: columnsFor(threads, multi),
      items: threads.map((thread) => ({ key: thread.sessionId, cells: cellsFor(thread) })),
    });
    if (!chosen) return 1;
    const thread = threads.find((candidate) => candidate.sessionId === chosen.key)!;
    process.stdout.write(`${thread.sessionId}\t${thread.cwd}\n`);
    return 0;
  }

  if (!threads.length) {
    console.log(`No Zed/ACP threads found (${scope}: ${directory})`);
    return 0;
  }

  if (process.stdout.isTTY) {
    printTable(threads, columnsFor(threads, multi), "pick one to resume with: resume-zed");
    return 0;
  }

  threads.forEach((thread) => {
    console.log(displayFor(thread, multi));
    console.log(`    ${resumeCommand(thread, multi)}`);
  });
  return 0;
};

process.exitCode = await main();
