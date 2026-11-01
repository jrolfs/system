import assert from "node:assert/strict";
import { setImmediate } from "node:timers/promises";
import { test } from "node:test";
import { createSync } from "./index.ts";

test("coalesces memory writes and flushes them on unload", async () => {
  const calls: string[] = [];
  const sync = createSync({ run: async (direction) => { calls.push(direction); }, warn: () => {} });
  await sync.pull();
  sync.changed();
  sync.changed();
  assert.deepEqual(calls, ["pull"]);
  await sync.stop();
  assert.deepEqual(calls, ["pull", "push"]);
});

test("pushes after the debounce, without needing a parent-session idle event", async (context) => {
  context.mock.timers.enable({ apis: ["setTimeout"] });
  const calls: string[] = [];
  const sync = createSync({ run: async (direction) => { calls.push(direction); }, warn: () => {} });
  sync.changed();
  context.mock.timers.tick(1_000);
  sync.changed();
  context.mock.timers.tick(1_000);
  await setImmediate();
  assert.deepEqual(calls, []);
  context.mock.timers.tick(1_000);
  await setImmediate();
  assert.deepEqual(calls, ["pull", "push"]);
  await sync.stop();
});

test("does not push if pulling failed, and retries after connectivity returns", async (context) => {
  context.mock.timers.enable({ apis: ["setTimeout"] });
  const calls: string[] = [];
  const warnings: string[] = [];
  let offline = true;
  const sync = createSync({
    run: async (direction) => {
      calls.push(direction);
      if (offline) throw new Error("offline");
    },
    warn: (direction) => { warnings.push(direction); },
  });
  assert.equal(await sync.pull(), false);
  sync.changed();
  await sync.flush();
  assert.deepEqual(calls, ["pull", "pull"]);
  assert.deepEqual(warnings, ["pull", "pull"]);
  offline = false;
  context.mock.timers.tick(30_000);
  await setImmediate();
  assert.deepEqual(calls, ["pull", "pull", "pull", "push"]);
  await sync.stop();
});

test("retries a failed push", async (context) => {
  context.mock.timers.enable({ apis: ["setTimeout"] });
  const calls: string[] = [];
  let failPush = true;
  const sync = createSync({
    run: async (direction) => {
      calls.push(direction);
      if (direction === "push" && failPush) throw new Error("offline");
    },
    warn: () => {},
  });
  await sync.pull();
  sync.changed();
  await sync.flush();
  failPush = false;
  context.mock.timers.tick(30_000);
  await setImmediate();
  assert.deepEqual(calls, ["pull", "push", "push"]);
  await sync.stop();
});

test("serializes commands and retains a save made during an upload", async () => {
  const calls: string[] = [];
  let finishPush: (() => void) | undefined;
  const sync = createSync({
    run: async (direction) => {
      calls.push(direction);
      if (direction === "push" && calls.length === 2) {
        await new Promise<void>((resolve) => { finishPush = resolve; });
      }
    },
    warn: () => {},
  });
  await sync.pull();
  sync.changed();
  const pushing = sync.flush();
  await setImmediate();
  const pulling = sync.pull();
  sync.changed();
  assert.deepEqual(calls, ["pull", "push"]);
  assert.ok(finishPush);
  finishPush();
  await Promise.all([pushing, pulling]);
  await sync.stop();
  assert.deepEqual(calls, ["pull", "push", "pull", "push"]);
});
