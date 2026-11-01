import { basename } from "node:path";

import { paintFor } from "./ansi.ts";
import { age, AGE_WIDTH, cell, GAP, layout, type Column } from "./table.ts";
import { momentOf, type ClaudeThread } from "./threads.ts";

const WHERE_MIN = 12;
const WHERE_MAX = 32;

/**
 * Columns for a thread list, with directories only when the scope spans them.
 */
export const columnsFor = (threads: readonly ClaudeThread[], multi: boolean): readonly Column[] => [
  { key: "age", header: "when", width: AGE_WIDTH, align: "right", tone: { dim: true } },
  ...(multi
    ? ([{
        key: "where",
        header: "worktree",
        min: WHERE_MIN,
        max: Math.min(WHERE_MAX, Math.max(WHERE_MIN, ...threads.map((thread) => basename(thread.cwd).length))),
        elide: "start",
        optional: true,
        tone: { color: "blue" },
      }] as const)
    : []),
  { key: "thread", header: "thread", flex: true, min: 24, elide: "end" },
];

/**
 * Display cells for a thread in either the table or the picker.
 */
export const cellsFor = (thread: ClaudeThread): Readonly<Record<string, string>> => ({
  age: age(momentOf(thread)),
  where: thread.cwd ? basename(thread.cwd) : "?",
  thread: thread.title || "(untitled)",
});

/**
 * Print a terminal-width thread table and its next-step hint.
 */
export const printTable = (
  threads: readonly ClaudeThread[],
  columns: readonly Column[],
  hint: string,
): void => {
  const paint = paintFor(process.stdout);
  const widths = layout(columns, (process.stdout.columns || 80) - 1);
  const shown = columns.filter((column) => widths.has(column.key));
  const line = (
    values: Readonly<Record<string, string>>,
    tone: (column: Column) => Parameters<typeof paint>[1],
  ): string =>
    shown.map((column, index) =>
      paint(cell(values[column.key] ?? "", widths.get(column.key)!, {
        elide: column.elide,
        align: column.align,
        pad: index < shown.length - 1,
      }), tone(column)),
    ).join(GAP);

  console.log(line(Object.fromEntries(shown.map((column) => [column.key, column.header])), () => ({ dim: true })));
  threads.forEach((thread) => console.log(line(cellsFor(thread), (column) => column.tone)));
  console.log(paint(hint, { dim: true }));
};
