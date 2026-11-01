/**
 * Claude Code threads, with an optional filter for Zed's ACP client.
 *
 * Zed drives Claude Code non-interactively, so its threads land in the same
 * per-project store as the terminal CLI but with a different fingerprint: the
 * first record carries `operation` and no `mode: "normal"`, where an
 * interactive session is the reverse.
 */
import { execFileSync } from "node:child_process";
import { closeSync, existsSync, openSync, readdirSync, readSync, statSync } from "node:fs";
import { StringDecoder } from "node:string_decoder";
import { basename, join, resolve } from "node:path";
import * as z from "zod";

import { PROJECTS_ROOT, slugFor } from "./store.ts";

// Transcripts run to tens of megabytes, and everything wanted here is at the
// top: the meta record is first, and the recorded cwd and opening user message
// follow within a few records. So read the first records rather than the file,
// in chunks, because a fixed byte window is the wrong unit: one
// file-history-snapshot record can be hundreds of kilobytes on its own and
// would push the opening message outside it.
const CHUNK_BYTES = 64 * 1024;
const HEAD_RECORDS = 40;

const contentSchema = z.union([
  z.string(),
  z.array(z.looseObject({ type: z.string().optional(), text: z.string().optional() })),
]);

const recordSchema = z.looseObject({
  type: z.string().optional(),
  cwd: z.string().optional(),
  operation: z.string().optional(),
  mode: z.string().optional(),
  isSidechain: z.boolean().optional(),
  customTitle: z.string().optional(),
  aiTitle: z.string().optional(),
  message: z.looseObject({ content: contentSchema.optional() }).optional(),
});

type TranscriptRecord = z.infer<typeof recordSchema>;

export interface ClaudeThread {
  readonly sessionId: string;
  readonly cwd: string;
  readonly title: string;
  readonly transcriptPath: string;
  /**
   * Nanoseconds since the epoch, not a Date: transcripts written in the same
   * millisecond are common enough that rounding reorders the list.
   */
  readonly modified: bigint;
}

export type ZedThread = ClaudeThread;

export type Scope = "here" | "repo" | "all";

/**
 * The first complete lines of a file, read a chunk at a time.
 *
 * Imperative because it stops as soon as enough lines have arrived: the files
 * this runs over are large and there are hundreds of them. The decoder holds
 * any multi-byte character split across a chunk boundary.
 */
const headLines = (path: string, wanted: number): readonly string[] => {
  const handle = openSync(path, "r");
  const decoder = new StringDecoder("utf8");
  const buffer = Buffer.alloc(CHUNK_BYTES);
  const lines: string[] = [];
  let carry = "";
  let position = 0;

  try {
    while (lines.length < wanted) {
      const read = readSync(handle, buffer, 0, CHUNK_BYTES, position);
      if (read === 0) break;
      position += read;
      const parts = (carry + decoder.write(buffer.subarray(0, read))).split("\n");
      carry = parts.pop() ?? "";
      lines.push(...parts);
    }
  } finally {
    closeSync(handle);
  }
  return lines.slice(0, wanted);
};

const headRecords = (path: string): readonly TranscriptRecord[] =>
  headLines(path, HEAD_RECORDS)
    .filter(Boolean)
    .map((line) => {
      try {
        return recordSchema.safeParse(JSON.parse(line));
      } catch {
        return undefined;
      }
    })
    .flatMap((parsed) => (parsed?.success ? [parsed.data] : []));

/** Whether a session's first record marks it as one of Zed's. */
const startedByZed = (meta: TranscriptRecord): boolean =>
  Boolean(meta.operation) && meta.mode !== "normal";

/**
 * Cut the markup an opening message carries down to what it says.
 *
 * A thread started from a slash command opens with the command's own envelope,
 * and one started from an editor selection opens with a markdown link whose
 * href is longer than the list is wide. Both would otherwise fill the row and
 * tell you nothing.
 */
const readable = (message: string): string =>
  message
    .replace(/<command-name>([^<]*)<\/command-name>/g, "$1")
    .replace(/<command-message>[^<]*<\/command-message>/g, "")
    .replace(/<command-args>([^<]*)<\/command-args>/g, "$1")
    .replace(/<[^>]+>[^<]*<\/[^>]+>/g, "")
    .replace(/\[@([^\]]+)\]\(file:\/\/[^)]*\)/g, "@$1")
    .replace(/\[([^\]]*)\]\((?:file|https?):\/\/[^)]*\)/g, "$1")
    .trim();

/** An assigned title if there is one, else the opening user message. */
const titleOf = (records: readonly TranscriptRecord[]): string => {
  const [meta] = records;
  const assigned = meta?.customTitle || meta?.aiTitle;
  if (assigned) return assigned;

  const opening = records.find((record) => record.type === "user")?.message?.content;
  const text =
    typeof opening === "string"
      ? opening
      : (opening?.find((part) => part.type === "text")?.text ?? "");
  return readable(text);
};

/** Absolute paths of every git worktree sharing this directory's repo. */
export const repoWorktrees = (start: string): readonly string[] => {
  try {
    const listing = execFileSync("git", ["-C", start, "worktree", "list", "--porcelain"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    const worktrees = listing
      .split("\n")
      .filter((line) => line.startsWith("worktree "))
      .map((line) => line.slice("worktree ".length));
    return worktrees.length ? worktrees : [resolve(start)];
  } catch {
    return [resolve(start)];
  }
};

const scanStore = (root: string, zedOnly: boolean): readonly ClaudeThread[] =>
  readdirSync(root)
    .filter((name) => name.endsWith(".jsonl"))
    .flatMap((name) => {
      const path = join(root, name);
      const records = headRecords(path);
      if (!records.length || (zedOnly && !startedByZed(records[0]!))) return [];
      if (!zedOnly && !records.some((record) => record.type === "user" && !record.isSidechain)) return [];
      return [
        {
          sessionId: name.replace(/\.jsonl$/, ""),
          transcriptPath: path,
          cwd: records.find((record) => record.cwd)?.cwd ?? "",
          title: titleOf(records).split(/\s+/).filter(Boolean).join(" "),
          modified: statSync(path, { bigint: true }).mtimeNs,
        },
      ];
    });

const storesFor = (directory: string, scope: Scope, projectsRoot: string): readonly string[] => {
  if (scope === "all") {
    if (!existsSync(projectsRoot)) return [];
    return readdirSync(projectsRoot, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => join(projectsRoot, entry.name));
  }
  const directories = scope === "repo" ? repoWorktrees(directory) : [directory];
  return directories.map((path) => join(projectsRoot, slugFor(path)));
};

export interface ThreadScanOptions {
  readonly projectsRoot?: string;
  readonly zedOnly?: boolean;
}

/**
 * Claude Code threads for the requested scope, newest first.
 */
export const claudeThreads = (
  directory: string,
  scope: Scope,
  { projectsRoot = PROJECTS_ROOT, zedOnly = false }: ThreadScanOptions = {},
): readonly ClaudeThread[] =>
  storesFor(directory, scope, projectsRoot)
    .filter((root) => existsSync(root))
    .flatMap((root) => scanStore(root, zedOnly))
    .sort(
      (left, right) =>
        Number(right.modified - left.modified) ||
        // Same tie-break as the list this replaced, so equal timestamps keep a
        // stable order rather than whichever the directory listing gave.
        right.sessionId.localeCompare(left.sessionId),
    );

/**
 * Zed threads for the requested scope, newest first.
 */
export const zedThreads = (directory: string, scope: Scope): readonly ZedThread[] =>
  claudeThreads(directory, scope, { zedOnly: true });

/** The thread's mtime as a date, for formatting. */
export const momentOf = (thread: ZedThread): Date =>
  new Date(Number(thread.modified / 1_000_000n));

export const TAG_WIDTH = 25;

/**
 * Short label for a thread's directory, keeping the distinguishing tail.
 *
 * Sibling worktrees share a long common prefix (`frontends.jamie-feature-...`)
 * and differ only at the end, so elide from the left rather than the right.
 */
export const projectTag = (cwd: string): string => {
  const name = cwd ? basename(cwd.replace(/\/+$/, "")) : "?";
  return name.length <= TAG_WIDTH ? name : `…${name.slice(-(TAG_WIDTH - 1))}`;
};

const pad = (value: number): string => String(value).padStart(2, "0");

export const when = (nanoseconds: bigint): string => {
  const moment = new Date(Number(nanoseconds / 1_000_000n));
  return (
    `${moment.getFullYear()}-${pad(moment.getMonth() + 1)}-${pad(moment.getDate())} ` +
    `${pad(moment.getHours())}:${pad(moment.getMinutes())}`
  );
};

export const displayFor = (thread: ZedThread, multi: boolean): string => {
  const label = thread.title.slice(0, 80) || "(untitled)";
  return multi
    ? `${when(thread.modified)}  ${projectTag(thread.cwd).padEnd(TAG_WIDTH)}  ${label}`
    : `${when(thread.modified)}  ${label}`;
};

export const resumeCommand = (thread: ZedThread, multi: boolean): string =>
  multi && thread.cwd
    ? `(cd ${thread.cwd} && claude --resume ${thread.sessionId})`
    : `claude --resume ${thread.sessionId}`;
