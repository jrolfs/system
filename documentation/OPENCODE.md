# OpenCode alongside Claude Code

`modules/home/shared/opencode.nix` declares OpenCode's settings and plugin
options through Home Manager. Supporting plugin sources live beside it under
`opencode-sync/`. The auto-permission plugin is pinned and patched in
`overlays/default.nix`. Do not edit the generated
`~/.config/opencode/opencode.json` directly.

## What is shared

- Instructions: the repository's `CLAUDE.md` files and `~/.claude/CLAUDE.md`.
- Skills: OpenCode discovers `.claude/skills` and `~/.claude/skills` natively.
  Worktrunk's skill comes from the installed package, not Claude's plugin loader.
- MCP declarations: `modules/home/shared/mcp.nix` feeds both clients. OAuth
  credentials are separate. Sign in to OpenCode's servers through `/mcps`.
- Memory: `opencode-claude-memory` uses Claude's existing
  `~/.claude/projects/<canonical-repo>/memory/` directory, including from linked
  worktrees. No conversion or extra memory store is needed.

Claude commands, agents, and plugins are not automatically interchangeable with
OpenCode's equivalents. The existing `/resume-zed` command is Claude-specific.

## Continue a Claude conversation

`resume-claude` opens the same Bun/React/Ink picker as `resume-zed`, but includes
terminal Claude Code threads as well as Zed/ACP threads and continues the
selection in OpenCode:

```sh
resume-claude                  # this directory
resume-claude --repo           # every current git worktree
resume-claude --all            # all local Claude projects
resume-claude -d /path/to/repo
resume-claude --all --import UUID
resume-claude --all --import UUID --into /new/directory
```

`claude-opencode-threads` lists threads without importing them. Piped output
includes exact resume commands. OpenCode's `/resume-claude` command uses that
listing to help find a thread without loading every transcript into context.
Run the shell function to open the imported session, since a slash command
cannot replace the conversation it is running inside.

The helper converts the saved active parent chain into OpenCode V2's session
transfer format and imports it through `opencode session import`. A saved
compaction summary replaces the earlier context as it does in Claude. User and
assistant text retain their roles. Historical tool calls and results become
text, never pending executable calls. Private thinking, provider signatures,
images and document attachments are not transferred. Placeholders and import
warnings make omissions visible. Claude's system records, permissions and
provider selection are not carried over. OpenCode uses its own configuration.
No model is run during the import, and the original Claude JSONL is untouched.

Each Claude UUID maps to one stable OpenCode session ID. Picking it again
resumes that continuation without overwriting OpenCode work or importing later
Claude changes. Missing working directories require an explicit `--into DIR`.
The temporary transfer file is private and removed after import. There is no
direct database access or database sync. The helper is packaged with
`pkgs.claude-helpers`, so script changes require a switch before using the
installed command.

## Memory sync

The Nix-built `opencode-claude-sync` plugin calls the same patched `claude-sync`
binary as Claude's hooks. It uses the existing encrypted B2 backend and
`~/.claude-sync` credentials. It does not add a backend or change sync scope.

1. It pulls before the memory plugin loads, including startup extraction of
   earlier conversations.
2. The first prompt in each top-level session pulls again before memory recall.
3. Successful `memory_save` and `memory_delete` tools queue a push after two
   quiet seconds. This includes the memory plugin's background extraction and
   consolidation sessions, which can finish after the main answer.
4. Transfers are serialized across plugin instances in the same server. Failed
   transfers retain pending writes and retry after 30 seconds. A failed initial
   pull blocks automatic pushes until a pull succeeds, not the conversation.

Plugin unload attempts a final flush. Force-killing the server can prevent a
pending upload. Direct file edits outside the memory tools do not trigger an
upload either. In either case, `claude-sync push -q` sends the files manually.
The plugin does not coordinate transfers with a separate Claude process or a
manually invoked `claude-sync`; avoid simultaneous manual transfers.

`wt handoff` already pushes `claude-sync`, and `wt restore` pulls it before
restoring worktrees. Those aliases need no changes for shared memory. A handoff
does not wait for an extraction agent that is still running, so let extraction
finish before moving machines or push again afterwards.

## What does not sync

OpenCode's conversations live in its own database. Neither the memory plugin
nor `wt handoff` converts them to Claude transcripts or transfers that database.
Do not sync the live SQLite file with `claude-sync` or a file-sync service.
Worktree files and durable memories transfer; resuming an OpenCode conversation
on a different machine remains separate work.

## Automatic permissions

The global default remains `ask`. Static safety denials run first. On personal
hosts with a TypeSafe key, Jev then handles confident decisions. Its
`fallbackOnAsk = true` option is provided by the local plugin patch: an `ask`,
including a low-confidence deny, reaches the immediately following LLM reviewer.
An explicit deny does not fall through. The option is off unless declared.

The final reviewer is Sonnet on personal hosts and Opus through Foundry on the
work host. If it asks, or no reviewer can decide, OpenCode prompts the user.
The reviewer is independent of the model doing the work.

Decisions are logged at `~/.local/state/opencode-auto-mode/decisions.jsonl`.
The memory plugin's log is under
`~/.claude/opencode-memory/<canonical-repo>/opencode-memory.log`. Its background
agents have their own configured models and billing, regardless of the current
conversation's model.

## Delegated model routing

Where this host has a TypeSafe key and personal provider keys, the Nix-built
`opencode-task-router` selects a model for new built-in `explore` and `general`
subagent calls. The pool and capability descriptions are declared in
`modules/home/shared/opencode.nix`:

| Model | Intended tasks |
| --- | --- |
| GPT-6 Luna | Straightforward lookups, summaries and boilerplate |
| Claude Sonnet 5.5 | Everyday implementation, refactoring and review |
| GPT-6.1 Sol | Deep code tracing, debugging and reasoning-heavy implementation |
| Claude Opus 5.5 | Architecture, ambiguous requirements and high-risk cross-module work |

Only models with keys on this host enter the declared pool. At delegation time,
the router also removes unavailable, disabled and non-tool-using models. Jev
receives the delegated task and capability descriptions, not the parent
conversation. It does not consider cost, provider priority or account balances.

A choice below 0.8 confidence, a malformed answer, or a failed five-second
request uses Opus, or Sol on an OpenAI-only host. If that fallback is unavailable,
the delegation inherits its usual model. The only eligible model is used
directly when the pool has just one.

Explicit tool-level models, agent-specific model settings, custom agents and
resumed subagents are left alone. The primary session, hidden memory agents and
permission reviewer are never rerouted. This does not create delegations by
itself or change whether the primary agent is allowed to delegate.

Selections appear in the OpenCode server log under `opencode-task-router`, with
the session, agent, selected model and routing reason, without the task text.
The Foundry-only work host has no TypeSafe key and does not load this router.
