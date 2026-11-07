import assert from "node:assert/strict";
import { test } from "node:test";
import { spacingCommand } from "./tui.ts";

const prefix = "\x1bP@kitty-cmd";
const terminator = "\x1b\\";

const decode = (sequence: string): unknown => {
  assert.ok(sequence.startsWith(prefix));
  assert.ok(sequence.endsWith(terminator));

  return JSON.parse(sequence.slice(prefix.length, -terminator.length));
};

test("zeroes every side of the pane the command is written to", () => {
  assert.deepEqual(decode(spacingCommand(0)), {
    cmd: "set-spacing",
    version: [0, 14, 2],
    no_response: true,
    payload: {
      match_window: "state:self",
      settings: { "padding-top": 0, "padding-right": 0, "padding-bottom": 0, "padding-left": 0 },
    },
  });
});

test("resets every side to the configured padding with null", () => {
  const { payload } = decode(spacingCommand(null)) as { payload: { settings: Record<string, unknown> } };

  assert.deepEqual(payload.settings, {
    "padding-top": null,
    "padding-right": null,
    "padding-bottom": null,
    "padding-left": null,
  });
});
