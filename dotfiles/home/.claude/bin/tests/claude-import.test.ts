import { afterEach, describe, expect, test } from "bun:test";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

import { convertTranscript, importedId, type ConversionOptions } from "../lib/claude-import.ts";
import { importThread } from "../lib/opencode-import.ts";
import { slugFor } from "../lib/store.ts";
import { claudeThreads } from "../lib/threads.ts";

const SESSION = "90417627-c8fc-4205-a46f-ce3483f5a1a8";
const OTHER = "561aae90-13ef-4dc8-b092-f2dfeb0cb3ea";
const options: Omit<ConversionOptions, "transcript"> = {
  sessionId: SESSION,
  directory: "/project",
  source: `/claude/${SESSION}.jsonl`,
  title: "Opening question",
  modified: 1793560000000,
};

interface RecordOptions {
  readonly uuid: string;
  readonly parentUuid: string | null;
  readonly type?: string;
  readonly content?: unknown;
  readonly isSidechain?: boolean;
}

const record = ({ type = "user", content = "Hello", ...rest }: RecordOptions) => ({
  ...rest,
  type,
  timestamp: "2026-11-01T10:00:00.000Z",
  cwd: "/project",
  message: { content, model: "claude-opus-5-5" },
});
const jsonl = (records: readonly unknown[]): string => records.map((value) => JSON.stringify(value)).join("\n") + "\n";
const convert = (records: readonly unknown[]) => convertTranscript({ ...options, transcript: jsonl(records) });
const opening = record({ uuid: "user-1", parentUuid: null });
const answer = record({ uuid: "assistant-1", parentUuid: "user-1", type: "assistant", content: [{ type: "text", text: "Answer" }] });

const temporaries: string[] = [];
const temporary = (): string => {
  const path = realpathSync(mkdtempSync(join(tmpdir(), "claude-import-test-")));
  temporaries.push(path);
  return path;
};
afterEach(() => temporaries.splice(0).forEach((path) => rmSync(path, { recursive: true, force: true })));

describe("Claude transcript conversion", () => {
  test("preserves roles, timestamps and provenance without importing configuration", () => {
    const { data } = convert([
      { type: "system", content: "old system instructions", permissions: ["allow everything"] },
      opening,
      answer,
      { type: "custom-title", customTitle: "Renamed later" },
    ]);
    expect(data.info.title).toBe("Renamed later");
    expect(data.info.id).toBe(importedId(SESSION));
    expect(data.info).not.toHaveProperty("model");
    expect(data.info).not.toHaveProperty("permissions");
    expect(data.info.metadata.claudeImport.sessionId).toBe(SESSION);
    expect(data.info.metadata.claudeImport.sha256).toHaveLength(64);
    expect(data.messages.map((message) => message.type)).toEqual(["synthetic", "user", "assistant"]);
    expect(data.messages[1]!.time.created).toBe(Date.parse("2026-11-01T10:00:00.000Z"));
    expect(JSON.stringify(data.messages)).not.toContain("old system instructions");
  });

  test("imports the latest parent chain, not abandoned branches or subagents", () => {
    const { data } = convert([
      opening,
      record({ uuid: "abandoned", parentUuid: "user-1", type: "assistant", content: "Wrong branch" }),
      answer,
      record({ uuid: "child", parentUuid: "assistant-1", type: "assistant", content: "Subagent", isSidechain: true }),
    ]);
    expect(JSON.stringify(data.messages)).toContain("Answer");
    expect(JSON.stringify(data.messages)).not.toMatch(/Wrong branch|Subagent/);
  });

  test("keeps the compacted context instead of duplicating earlier history", () => {
    const { data } = convert([
      opening, answer,
      { type: "system", subtype: "compact_boundary", uuid: "compact", parentUuid: null },
      record({ uuid: "summary", parentUuid: "compact", content: "Saved compaction summary" }),
      record({ uuid: "new", parentUuid: "summary", content: "Continue" }),
    ]);
    expect(JSON.stringify(data.messages)).toContain("Saved compaction summary");
    expect(JSON.stringify(data.messages)).not.toContain("Answer");
  });

  test("quotes historical tool input and output without creating executable tool parts", () => {
    const { data } = convert([
      opening,
      record({ uuid: "call", parentUuid: "user-1", type: "assistant", content: [
        { type: "text", text: "Inspecting" },
        { type: "tool_use", id: "call-1", name: "Bash", input: { command: "echo example" } },
      ] }),
      record({ uuid: "result", parentUuid: "call", content: [
        { type: "tool_result", tool_use_id: "call-1", is_error: true, content: [{ type: "text", text: "Saved output" }] },
      ] }),
    ]);
    const serialized = JSON.stringify(data.messages);
    expect(serialized).toContain("echo example");
    expect(serialized).toContain("Saved output");
    expect(serialized).toContain("call-1, error");
    expect(serialized).not.toContain('"type":"tool"');
  });

  test("reports attachment omissions and removes thinking and signatures", () => {
    const { data, warnings } = convert([
      opening,
      record({ uuid: "answer", parentUuid: "user-1", type: "assistant", content: [
        { type: "thinking", thinking: "private reasoning", signature: "secret signature" },
        { type: "image", source: { data: "base64-data" } },
        { type: "document", source: { data: "document-bytes" } },
        { type: "text", text: "Public answer" },
      ] }),
    ]);
    expect(warnings).toHaveLength(3);
    expect(JSON.stringify(data)).not.toMatch(/private reasoning|secret signature|base64-data|document-bytes/);
    expect(JSON.stringify(data.messages)).toContain("image content not imported");
    expect(JSON.stringify(data.messages)).toContain("Public answer");
  });

  test("ignores only a partial final JSONL record", () => {
    const result = convertTranscript({ ...options, transcript: jsonl([opening, answer]) + '{"type":' });
    expect(result.data.messages).toHaveLength(3);
    expect(result.warnings).toContain("An incomplete final transcript record was not imported.");
    expect(() => convertTranscript({ ...options, transcript: jsonl([opening]) + "broken\n" + jsonl([answer]) })).toThrow("line 2");
    expect(() => convertTranscript({ ...options, transcript: JSON.stringify({ type: 123 }) })).toThrow("unsupported");
  });

  test("rejects cycles and empty conversations", () => {
    expect(() => convert([record({ uuid: "loop", parentUuid: "loop" })])).toThrow("cycle");
    expect(() => convert([{ type: "system" }])).toThrow("no user conversation");
  });

  test("warns when the saved branch starts at a missing parent", () => {
    const { warnings } = convert([record({ uuid: "summary", parentUuid: "missing", content: "Saved summary" })]);
    expect(warnings).toContain("Earlier history is absent from the saved parent chain.");
  });

  test("gives copied fork messages different global IDs and validates session UUIDs", () => {
    const first = convert([opening, answer]);
    const second = convertTranscript({ ...options, sessionId: OTHER, transcript: jsonl([opening, answer]) });
    expect(first.data.messages[1]!.id).not.toBe(second.data.messages[1]!.id);
    expect(() => importedId("../../other")).toThrow();
  });

  test("handles legacy unlinked records in file order", () => {
    const { data } = convert([
      { type: "user", message: { content: "Legacy question" } },
      { type: "assistant", message: { content: "Legacy answer" } },
    ]);
    expect(data.messages).toHaveLength(3);
    expect(data.messages[2]!.time.created).toBe(options.modified);
  });
});

describe("command line", () => {
  const run = (...arguments_: readonly string[]) => spawnSync(process.execPath, [
    resolve(import.meta.dir, "../claude-opencode-threads.tsx"), ...arguments_,
  ], { encoding: "utf8", env: { ...process.env, HOME: temporary() } });

  test("rejects conflicting scopes and path traversal before contacting OpenCode", () => {
    expect(run("--repo", "--all").status).toBe(1);
    expect(run("--pick", "--import", SESSION).status).toBe(1);
    expect(run("--import", "../../other").status).toBe(1);
  });

  test("requires a terminal for picking and handles an empty store", () => {
    expect(run("--pick").stderr).toContain("needs a terminal");
    const result = run("--all");
    expect(result.status).toBe(0);
    expect(result.stdout).toContain("No Claude threads found");
  });
});

describe("thread discovery", () => {
  test("includes terminal and ACP conversations, excluding nested subagent stores", () => {
    const projectsRoot = temporary();
    const store = join(projectsRoot, slugFor("/project"));
    mkdirSync(join(store, "subagents"), { recursive: true });
    writeFileSync(join(store, `${SESSION}.jsonl`), jsonl([{ mode: "normal" }, opening, answer]));
    writeFileSync(join(store, `${OTHER}.jsonl`), jsonl([{ operation: "enqueue" }, opening, answer]));
    writeFileSync(join(store, "subagents", "agent.jsonl"), jsonl([opening]));
    expect(claudeThreads("/project", "here", { projectsRoot })).toHaveLength(2);
    expect(claudeThreads("/project", "here", { projectsRoot, zedOnly: true }).map((thread) => thread.sessionId)).toEqual([OTHER]);
    expect(claudeThreads("/elsewhere", "here", { projectsRoot })).toEqual([]);
    expect(claudeThreads("/elsewhere", "all", { projectsRoot })).toHaveLength(2);
  });

  test("keeps the actual source path when the recorded working directory moved", () => {
    const projectsRoot = temporary();
    const store = join(projectsRoot, slugFor("/old-project"));
    mkdirSync(store);
    const source = join(store, `${SESSION}.jsonl`);
    writeFileSync(source, jsonl([opening, answer]));
    const [thread] = claudeThreads("/old-project", "here", { projectsRoot });
    expect(thread!.cwd).toBe("/project");
    expect(thread!.transcriptPath).toBe(source);
  });

  test("repo scope includes only registered worktrees", () => {
    const root = temporary();
    const repository = join(root, "repo");
    const sibling = join(root, "sibling");
    const projectsRoot = join(root, "projects");
    mkdirSync(repository);
    execFileSync("git", ["init", "-q", repository]);
    execFileSync("git", ["-C", repository, "-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false", "commit", "--allow-empty", "-qm", "initial"]);
    execFileSync("git", ["-C", repository, "worktree", "add", "-qb", "test-sibling", sibling]);
    [repository, sibling, "/unrelated"].forEach((directory) => {
      const store = join(projectsRoot, slugFor(directory));
      mkdirSync(store, { recursive: true });
      writeFileSync(join(store, `${directory === sibling ? OTHER : SESSION}.jsonl`), jsonl([opening]));
    });
    expect(claudeThreads(repository, "repo", { projectsRoot })).toHaveLength(2);
  });

  test("returns an empty list for a nonexistent Claude store", () => {
    expect(claudeThreads("/project", "all", { projectsRoot: join(temporary(), "absent") })).toEqual([]);
  });
});

// Opt in locally. Nix builds need neither a running service nor an OpenCode
// executable, while this checks the real installed V2 importer in isolation.
test.skipIf(!process.env.OPENCODE_IMPORT_TEST)("round-trips through the real OpenCode CLI and resumes without overwriting", () => {
  const root = temporary();
  const directory = join(root, "project with spaces");
  const bin = join(root, "bin");
  mkdirSync(directory);
  mkdirSync(bin);
  const executable = execFileSync("which", ["opencode"], { encoding: "utf8" }).trim();
  writeFileSync(join(bin, "opencode"), `#!/bin/sh\nexec '${executable.replaceAll("'", "'\\''")}' "$@" --standalone\n`, { mode: 0o700 });
  const source = join(root, `${SESSION}.jsonl`);
  const transcript = jsonl([opening, answer]);
  writeFileSync(source, transcript, { mode: 0o600 });
  const environment = { ...process.env };
  try {
    Object.assign(process.env, {
      HOME: root,
      XDG_CONFIG_HOME: join(root, "config"),
      XDG_DATA_HOME: join(root, "data"),
      XDG_CACHE_HOME: join(root, "cache"),
      XDG_STATE_HOME: join(root, "state"),
      PATH: `${bin}:${process.env.PATH}`,
      TMPDIR: root,
    });
    delete process.env.OPENCODE_SESSION_ID;
    const thread = { sessionId: SESSION, cwd: directory, title: "Test import", modified: 1793560000000000000n, transcriptPath: source };
    const imported = importThread({ thread });
    expect(imported).toEqual({ id: importedId(SESSION), directory });
    expect(readFileSync(source, "utf8")).toBe(transcript);
    const exported = JSON.parse(execFileSync("opencode", ["session", "export", imported.id], { encoding: "utf8", maxBuffer: 1024 * 1024 }));
    expect(exported.messages.map((message: { readonly type: string }) => message.type)).toEqual(["synthetic", "user", "assistant"]);
    expect(exported.messages[2].content[0].text).toBe("Answer");
    expect(exported.info).not.toHaveProperty("model");
    const missing = { ...thread, sessionId: OTHER, cwd: join(root, "missing") };
    expect(() => importThread({ thread: missing })).toThrow("thread directory is missing");
    expect(importThread({ thread: missing, into: directory })).toEqual({ id: importedId(OTHER), directory });
    writeFileSync(source, "changed after import\n");
    expect(importThread({ thread })).toEqual(imported);
    expect(() => importThread({ thread, into: root })).toThrow("already imported");
    expect(statSync(source).mode & 0o777).toBe(0o600);
    expect(readFileSync(source, "utf8")).toBe("changed after import\n");
    expect(existsSync(join(root, "data"))).toBe(true);
  } finally {
    Object.keys(process.env).filter((key) => !(key in environment)).forEach((key) => delete process.env[key]);
    Object.assign(process.env, environment);
  }
}, 120_000);
