import { createHash } from "node:crypto";
import * as z from "zod";

const recordSchema = z.looseObject({
  type: z.string().optional(),
  uuid: z.string().optional(),
  parentUuid: z.string().nullable().optional(),
  isSidechain: z.boolean().optional(),
  timestamp: z.string().optional(),
  cwd: z.string().optional(),
  customTitle: z.string().optional(),
  aiTitle: z.string().optional(),
  message: z.looseObject({
    content: z.unknown().optional(),
    model: z.string().optional(),
  }).optional(),
});

type TranscriptRecord = z.infer<typeof recordSchema>;

interface MessageBase {
  readonly id: string;
  readonly time: { readonly created: number; readonly completed?: number };
  readonly metadata?: Readonly<Record<string, unknown>>;
}

export interface ImportedUser extends MessageBase {
  readonly type: "user" | "synthetic";
  readonly text: string;
}

export interface ImportedAssistant extends MessageBase {
  readonly type: "assistant";
  readonly agent: string;
  readonly model: { readonly providerID: string; readonly id: string };
  readonly content: readonly { readonly type: "text"; readonly text: string }[];
  readonly finish: "stop";
}

export interface ConversionOptions {
  readonly sessionId: string;
  readonly directory: string;
  readonly source: string;
  readonly transcript: string;
  readonly title: string;
  readonly modified: number;
}

/**
 * The stable OpenCode ID for the first imported snapshot of a Claude thread.
 */
export const importedId = (sessionId: string): string =>
  `ses_claude_${z.uuid().parse(sessionId).replaceAll("-", "")}`;

const parseTranscript = (text: string, warnings: Set<string>): readonly TranscriptRecord[] => {
  const lines = text.split("\n");
  return lines.flatMap((line, index) => {
    if (!line.trim()) return [];
    const parsed: unknown = (() => {
      try {
        return JSON.parse(line);
      } catch {
        // Claude may still be appending. Only an incomplete final line is safe
        // to ignore; damage in the middle must not silently remove history.
        if (index === lines.length - 1 && !text.endsWith("\n")) {
          warnings.add("An incomplete final transcript record was not imported.");
          return undefined;
        }
        throw new Error(`invalid Claude transcript record at line ${index + 1}`);
      }
    })();
    if (parsed === undefined) return [];
    const record = recordSchema.safeParse(parsed);
    if (!record.success) {
      throw new Error(`unsupported Claude transcript record at line ${index + 1}`);
    }
    return [record.data];
  });
};

const activeBranch = (records: readonly TranscriptRecord[], warnings: Set<string>): readonly TranscriptRecord[] => {
  const main = records.filter((record) => !record.isSidechain);
  const linked = main.filter((record) => record.uuid && Object.hasOwn(record, "parentUuid"));
  if (!linked.length) return main;

  // A JSONL file also holds abandoned branches and pre-compaction history.
  // Walking the final parent chain matches what resume sees, rather than
  // treating every append as another turn in one conversation.
  const byId = new Map(linked.map((record) => [record.uuid!, record]));
  const seen = new Set<string>();
  const branch: TranscriptRecord[] = [];
  let current: TranscriptRecord | undefined = linked.at(-1);
  while (current) {
    if (seen.has(current.uuid!)) throw new Error("cycle in Claude transcript parent chain");
    seen.add(current.uuid!);
    branch.push(current);
    const parent: string | null | undefined = current.parentUuid;
    current = parent ? byId.get(parent) : undefined;
    if (parent && !current) warnings.add("Earlier history is absent from the saved parent chain.");
  }
  return branch.reverse();
};

const blockSchema = z.looseObject({
  type: z.string(),
  text: z.string().optional(),
  name: z.string().optional(),
  id: z.string().optional(),
  tool_use_id: z.string().optional(),
  is_error: z.boolean().optional(),
  input: z.unknown().optional(),
  content: z.unknown().optional(),
});

const contentText = (content: unknown, warnings: Set<string>): string => {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content.map((value: unknown) => {
    const parsed = blockSchema.safeParse(value);
    if (!parsed.success) {
      warnings.add("Unrecognized content blocks were replaced with placeholders.");
      return "[Unrecognized Claude content block]";
    }
    const block = parsed.data;
    switch (block.type) {
      case "text": return block.text ?? "";
      case "thinking":
      case "redacted_thinking":
        warnings.add("Private thinking and provider signatures were not imported.");
        return "";
      case "tool_use":
        return `[Historical Claude tool call: ${block.name ?? "?"} (${block.id ?? "?"})]\n${JSON.stringify(block.input ?? {}, null, 2)}`;
      case "tool_result":
        return `[Historical Claude tool result: ${block.tool_use_id ?? "?"}${block.is_error ? ", error" : ""}]\n${contentText(block.content, warnings)}`;
      default:
        warnings.add(`Content of type ${block.type} was replaced with a placeholder.`);
        return `[Claude ${block.type} content not imported. See the original transcript.]`;
    }
  }).filter(Boolean).join("\n\n");
};

/**
 * Convert the saved active conversation into an inert OpenCode V2 transcript.
 */
export const convertTranscript = (options: ConversionOptions) => {
  const warnings = new Set<string>();
  const records = parseTranscript(options.transcript, warnings);
  const branch = activeBranch(records, warnings);
  const messages = branch.flatMap<ImportedUser | ImportedAssistant>((record, index) => {
    if (record.type !== "user" && record.type !== "assistant") return [];
    const text = contentText(record.message?.content, warnings);
    if (!text.trim()) return [];
    const timestamp = Date.parse(record.timestamp ?? "");
    const created = Number.isFinite(timestamp) ? timestamp : options.modified;
    // Forks copy Claude UUIDs into several transcripts. Message IDs must be
    // unique across OpenCode sessions, not just within the imported branch.
    const digest = createHash("sha256")
      .update(`${options.sessionId}:${record.uuid ?? index}`)
      .digest("hex");
    const base = { id: `msg_claude_${digest}`, metadata: { claudeUuid: record.uuid } };
    return record.type === "user"
      ? [{ ...base, type: "user", time: { created }, text }]
      : [{
          ...base,
          type: "assistant",
          time: { created, completed: created },
          agent: "build",
          model: { providerID: "anthropic", id: record.message?.model ?? "claude-imported" },
          content: [{ type: "text", text }],
          finish: "stop",
        }];
  });
  if (!messages.some((message) => message.type === "user")) {
    throw new Error("no user conversation found in the saved active branch");
  }

  const created = messages[0]!.time.created;
  const title = records.toReversed().find((record) => record.customTitle || record.aiTitle);
  const note: ImportedUser = {
    id: `msg_claude_${options.sessionId.replaceAll("-", "")}_source`,
    type: "synthetic",
    time: { created },
    text: [
      `Imported from Claude Code session ${options.sessionId}.`,
      `Original transcript: ${options.source}`,
      "Historical tool calls and results are text, not pending actions. Nothing was re-executed.",
      "Continue using OpenCode's current instructions, tools and selected model, not the old tool names or permissions.",
      ...warnings,
    ].join("\n"),
  };
  return {
    warnings: [...warnings],
    data: {
      info: {
        id: importedId(options.sessionId),
        // Import resolves the real project from the explicit destination.
        projectID: "global",
        title: title?.customTitle || title?.aiTitle || options.title || "Imported Claude thread",
        location: { directory: options.directory },
        cost: 0,
        tokens: { input: 0, output: 0, reasoning: 0, cache: { read: 0, write: 0 } },
        time: { created, updated: options.modified },
        metadata: {
          claudeImport: {
            sessionId: options.sessionId,
            source: options.source,
            sha256: createHash("sha256").update(options.transcript).digest("hex"),
          },
        },
      },
      messages: [note, ...messages],
    },
  };
};
