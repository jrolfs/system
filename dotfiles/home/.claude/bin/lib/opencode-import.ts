import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import * as z from "zod";

import { convertTranscript, importedId } from "./claude-import.ts";
import { type ClaudeThread } from "./threads.ts";

const sessionSchema = z.object({
  data: z.object({
    id: z.string(),
    location: z.object({ directory: z.string() }),
    metadata: z.object({ claudeImport: z.object({ sessionId: z.string() }) }).optional(),
  }),
});

const lookup = (id: string) => {
  const result = spawnSync("opencode", ["api", "get", `/api/session/${id}`], { encoding: "utf8" });
  if (result.error) throw result.error;
  const body: unknown = JSON.parse(result.stdout || "null");
  if (result.status === 0) return sessionSchema.parse(body).data;
  if (z.object({ _tag: z.literal("SessionNotFoundError") }).safeParse(body).success) return undefined;
  throw new Error(`OpenCode session lookup failed: ${result.stderr || result.stdout}`);
};

export interface ImportOptions {
  readonly thread: ClaudeThread;
  readonly into?: string;
}

/**
 * Import a Claude snapshot once, or return its existing OpenCode continuation.
 */
export const importThread = ({ thread, into }: ImportOptions) => {
  const id = importedId(thread.sessionId);
  const existing = lookup(id);
  if (existing) {
    if (existing.metadata?.claudeImport.sessionId !== thread.sessionId) {
      throw new Error(`OpenCode session ID collision: ${id}`);
    }
    if (into && into !== existing.location.directory) {
      throw new Error(`already imported into ${existing.location.directory}; move that OpenCode session explicitly`);
    }
    console.error("Resuming the existing OpenCode continuation. Later Claude edits are not re-imported.");
    return { id, directory: existing.location.directory };
  }

  const directory = into ?? thread.cwd;
  if (!directory || !statSync(directory, { throwIfNoEntry: false })?.isDirectory()) {
    throw new Error(`thread directory is missing: ${directory || "(unknown)"}; pass --into DIR to choose a destination`);
  }
  const converted = convertTranscript({
    sessionId: thread.sessionId,
    directory,
    source: thread.transcriptPath,
    transcript: readFileSync(thread.transcriptPath, "utf8"),
    title: thread.title,
    modified: Number(thread.modified / 1_000_000n),
  });
  converted.warnings.forEach((warning) => console.error(warning));

  // The CLI handles service discovery and authentication. A private file
  // avoids putting large transcripts or their sensitive contents in argv.
  const temporary = mkdtempSync(join(tmpdir(), "claude-opencode-"));
  try {
    const file = join(temporary, "session.json");
    writeFileSync(file, JSON.stringify(converted.data), { mode: 0o600 });
    const result = spawnSync("opencode", ["session", "import", file, "--directory", directory], { encoding: "utf8" });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`OpenCode import failed: ${result.stderr || result.stdout}`);
    // Some CLI versions return success for a conflicting ID. Reading it back
    // also ensures we never print a ready-to-resume ID for an absent session.
    const imported = lookup(id);
    if (imported?.metadata?.claudeImport.sessionId !== thread.sessionId) {
      throw new Error(`OpenCode did not confirm the imported session: ${id}`);
    }
    return { id, directory: imported.location.directory };
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
};
