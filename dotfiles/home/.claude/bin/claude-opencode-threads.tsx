#!/usr/bin/env bun
import { resolve } from "node:path";
import * as z from "zod";

import { fail, flag, parse } from "./lib/cli.ts";
import { importThread } from "./lib/opencode-import.ts";
import { cellsFor, columnsFor, printTable } from "./lib/thread-table.ts";
import { claudeThreads, displayFor, type Scope } from "./lib/threads.ts";

const USAGE = "usage: claude-opencode-threads [-d DIR] [--repo | --all] [--pick | --import ID [--into DIR]]";
const quote = (value: string): string => `'${value.replaceAll("'", "'\\''")}'`;

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
      pick: { type: "boolean" },
      import: { type: "string" },
      into: { type: "string" },
    },
    schema: z.object({
      dir: z.string().default(process.cwd()),
      repo: flag,
      all: flag,
      pick: flag,
      import: z.uuid().optional(),
      into: z.string().optional(),
      positionals: z.array(z.string()).max(0, "takes no positionals"),
    })
      .refine((value) => !(value.repo && value.all), "pass --repo or --all, not both")
      .refine((value) => !(value.pick && value.import), "pass --pick or --import, not both")
      .refine((value) => !value.into || value.import || value.pick, "--into needs --pick or --import"),
  });

  const directory = resolve(args.dir);
  const scope: Scope = args.repo ? "repo" : args.all ? "all" : "here";
  // A moved project can leave the same UUID in two stores. Keep the newest
  // copy so picker keys and exact resume commands still identify one row.
  const seen = new Set<string>();
  const threads = claudeThreads(directory, scope).filter((thread) => {
    if (seen.has(thread.sessionId)) return false;
    seen.add(thread.sessionId);
    return true;
  });
  const multi = scope !== "here";

  if (args.import || args.pick) {
    if (args.pick && !process.stdin.isTTY) return fail("--pick needs a terminal on stdin");
    if (!threads.length) return fail(`no Claude threads found (${scope}: ${directory})`);
    const chosenId = args.import ?? (await (await import("./lib/picker.tsx")).pick({
      heading: `claude → opencode · ${scope}`,
      columns: columnsFor(threads, multi),
      items: threads.map((thread) => ({ key: thread.sessionId, cells: cellsFor(thread) })),
    }))?.key;
    if (!chosenId) return 130;
    const thread = threads.find((candidate) => candidate.sessionId === chosenId);
    if (!thread) return fail(`Claude thread not found in this scope: ${chosenId}`);
    const location = importThread({
      thread,
      into: args.into ? resolve(args.into) : undefined,
    });
    process.stdout.write(`${location.id}\t${location.directory}\n`);
    return 0;
  }

  if (!threads.length) {
    console.log(`No Claude threads found (${scope}: ${directory})`);
    return 0;
  }
  if (process.stdout.isTTY) {
    printTable(threads, columnsFor(threads, multi), "pick one to continue in OpenCode with: resume-claude");
    return 0;
  }
  threads.forEach((thread) => {
    console.log(displayFor(thread, multi));
    console.log(`    resume-claude --all --import ${thread.sessionId}`);
    console.log(`    transcript: ${quote(thread.transcriptPath)}`);
  });
  return 0;
};

try {
  process.exitCode = await main();
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}
