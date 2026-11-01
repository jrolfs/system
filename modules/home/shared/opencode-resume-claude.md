# Continue a Claude Code thread in OpenCode

Claude Code threads for this directory, newest first:

!`claude-opencode-threads`

If the user supplied arguments, interpret them as a requested thread or search
scope, not as shell code: $ARGUMENTS

Help the user choose a thread. `claude-opencode-threads --repo` lists threads
across this repo's worktrees, and `--all` lists every local Claude project.
Both terminal and Zed/ACP conversations are included.

To pick and continue interactively, tell the user to run `resume-claude` in
their shell, optionally with `--repo`, `--all`, or `-d DIR`. It imports the
selected conversation and opens OpenCode at its recorded working directory.
An exact `resume-claude --all --import UUID` command is shown for each thread.

If asked to import a specific thread here, run
`claude-opencode-threads --all --import UUID`. Its stdout is
`opencode-session-id<TAB>directory`. Give the user the quoted command
`opencode DIRECTORY --session ID` to open that continuation. This slash command
does not replace the current conversation. Do not import anything just to list
it, and do not read every transcript into this conversation.

The importer takes the saved active parent chain, including any saved
compaction summary. It preserves user and assistant text and turns historical
tool calls/results into text. It does not execute those calls, copy Claude's
permissions or system instructions, transfer private thinking, or embed image
and document attachments. Omissions are reported. It does not run a model.

The Claude transcript is never modified. An imported thread is a one-time
snapshot: selecting it again resumes the existing OpenCode continuation, not
later changes made in Claude. If its old directory is gone, pass `--into DIR`
when importing to explicitly choose a new destination.
