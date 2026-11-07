import { spawnSync } from "node:child_process";
import { writeSync } from "node:fs";

type Padding = 0 | null;

/**
 * Encode the kitty remote control command that sets the padding of the pane it
 * is written to, or resets it to `window_padding_width` when `padding` is null.
 */
export const spacingCommand = (padding: Padding): string => {
  const settings = Object.fromEntries(
    ["top", "right", "bottom", "left"].map((side) => [`padding-${side}`, padding]),
  );
  const command = {
    cmd: "set-spacing",
    version: [0, 14, 2],
    no_response: true,
    payload: { match_window: "state:self", settings },
  };

  return `\x1bP@kitty-cmd${JSON.stringify(command)}\x1b\\`;
};

// In-band over the TUI's own tty, so `state:self` is the pane opencode is
// drawing in, and nothing has to be spawned to send it.
const setPadding = (padding: Padding): void => {
  writeSync(process.stdout.fd, spacingCommand(padding));
};

// Bun keeps process.stdout's size until it handles SIGWINCH, which can't happen
// inside a synchronous exit handler, so this asks the tty itself.
const windowSize = (): string =>
  spawnSync("stty", ["size"], { stdio: ["inherit", "pipe", "ignore"] }).stdout?.toString() ?? "";

const pause = new Int32Array(new SharedArrayBuffer(4));

// kitty resizes the pane a few milliseconds after it reads the command. Handing
// the terminal back sooner leaves the shell drawing its prompt at opencode's
// width, and kitty's rewrap then strands zsh's partial-line `%` above it.
const restorePadding = (): void => {
  const before = windowSize();
  const started = Date.now();

  setPadding(null);
  while (windowSize() === before && Date.now() - started < 250) Atomics.wait(pause, 0, 0, 2);
};

// Registered once for the whole process rather than per setup: opencode also
// runs cleanup on every plugin reload, where restoring would flash the padding
// back, and a listener removed by cleanup would be gone before the exit.
let following = false;

const followProcess = (): void => {
  if (following) return;
  following = true;

  process.on("exit", restorePadding);

  // Ctrl-Z is opencode's terminal.suspend command, which ends by sending itself
  // SIGTSTP. Listening cancels the default stop, so the listener is a one-shot
  // that raises SIGTSTP again once the padding is back, and SIGCONT rearms it.
  let armed = false;

  const arm = (): void => {
    if (armed) return;
    armed = true;

    process.once("SIGTSTP", () => {
      armed = false;
      restorePadding();
      process.kill(process.pid, "SIGTSTP");
    });
  };

  arm();
  process.on("SIGCONT", () => {
    arm();
    setPadding(0);
  });
};

export default {
  id: "kitty-padding",
  setup: (): void => {
    if (process.env.TERM !== "xterm-kitty") return;

    followProcess();
    setPadding(0);
  },
};
