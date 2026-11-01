import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { Plugin } from "@opencode/plugin";

type Direction = "pull" | "push";

interface SyncOptions {
  readonly run: (direction: Direction) => Promise<void>;
  readonly warn: (direction: Direction) => void;
  readonly debounceMs?: number;
  readonly retryMs?: number;
}

/**
 * Queue memory sync without overlapping commands or blocking memory writes.
 */
export const createSync = ({ run, warn, debounceMs = 2_000, retryMs = 30_000 }: SyncOptions) => {
  let queue = Promise.resolve();
  let timer: ReturnType<typeof setTimeout> | undefined;
  let pulled = false;
  let dirty = false;
  let stopped = false;

  const enqueue = <T>(operation: () => Promise<T>): Promise<T> => {
    const result = queue.then(operation);
    queue = result.then(() => {}, () => {});
    return result;
  };

  const transfer = async (direction: Direction): Promise<boolean> => {
    try {
      await run(direction);
      return true;
    } catch {
      warn(direction);
      return false;
    }
  };

  const cancelTimer = (): void => {
    clearTimeout(timer);
    timer = undefined;
  };

  const schedule = (delay: number): void => {
    cancelTimer();
    if (stopped) return;
    timer = setTimeout(() => { void flush(); }, delay);
    timer.unref();
  };

  const pull = (): Promise<boolean> => enqueue(async () => {
    pulled = await transfer("pull");
    return pulled;
  });

  const flush = (): Promise<void> => enqueue(async () => {
    cancelTimer();
    if (!dirty) return;
    // A failed startup pull must not turn stale local files into remote updates.
    if (!pulled) pulled = await transfer("pull");
    if (!pulled) {
      schedule(retryMs);
      return;
    }
    dirty = false;
    const uploaded = await transfer("push");
    if (!uploaded) dirty = true;
    // A save during the upload needs another pass, even if that upload succeeded.
    if (dirty) schedule(uploaded ? debounceMs : retryMs);
  });

  return {
    pull,
    flush,
    changed: (): void => {
      dirty = true;
      schedule(debounceMs);
    },
    stop: async (): Promise<void> => {
      stopped = true;
      cancelTimer();
      await flush();
    },
  };
};

interface SharedSync {
  readonly sync: ReturnType<typeof createSync>;
  references: number;
}

// One server loads this plugin for multiple locations, all using the same sync state.
const coordinators = new Map<string, SharedSync>();
const executeFile = promisify(execFile);

export default {
  id: "opencode-claude-sync",
  setup: async (ctx: Plugin.Context): Promise<Plugin.Cleanup> => {
    const command = ctx.options.command;
    if (typeof command !== "string" || !command.startsWith("/")) {
      throw new Error("opencode-claude-sync requires an absolute command path");
    }

    const shared = coordinators.get(command) ?? {
      references: 0,
      sync: createSync({
        run: async (direction) => {
          await executeFile(command, [direction, "-q"], { timeout: 30_000 });
        },
        warn: (direction) => {
          console.warn(`[opencode-claude-sync] ${direction} failed. Run claude-sync ${direction} for details. Unsynced changes remain local.`);
        },
      }),
    };
    shared.references += 1;
    coordinators.set(command, shared);
    const sessions = new Set<string>();
    const registrations: Array<{ dispose(): Promise<void> }> = [];

    const cleanup = async (): Promise<void> => {
      await Promise.allSettled(registrations.map((registration) => registration.dispose()));
      shared.references -= 1;
      if (shared.references > 0) return;
      coordinators.delete(command);
      await shared.sync.stop();
    };

    try {
      // Plugin order puts this before memory setup, including its startup catch-up.
      await shared.sync.pull();
      registrations.push(await ctx.session.hook("prompt", async ({ sessionID }) => {
        if (sessions.has(sessionID)) return;
        const session = await ctx.session.get({ sessionID });
        if (session.parentID) return;
        if (await shared.sync.pull()) sessions.add(sessionID);
      }));
      registrations.push(await ctx.tool.hook("execute.after", (event) => {
        // Extraction and consolidation run later in hidden sessions. Their completed
        // tools, not the parent session's idle event, tell us the files were written.
        if (event.status !== "completed") return;
        if (event.tool === "memory_save" || event.tool === "memory_delete") shared.sync.changed();
      }));
    } catch (error) {
      await cleanup();
      throw error;
    }
    return cleanup;
  },
};
