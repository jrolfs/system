#!/usr/bin/env python
"""Open worktrunk's worktree picker in this tab's shell pane.

Deliberately not a picker of its own. `wt switch` already shows diff previews
and per-branch status, and running it where you would have typed it means the
window whose id the post-switch hook reads (worktree/switch.py) is one that is
still around when the hook fires, which an overlay closing on exit is not.
"""


def main(args):
    pass


def shell_pane(tab):
    """The pane to type into: tagged if the session file said so, else idle.

    The fallback covers a tab opened before the tags existed, and is safe
    because `has_running_program` is true for the Claude pane and for the
    editor, so the only pane it can land on is one sitting at a prompt.
    """
    windows = list(tab.windows)
    for window in windows:
        if getattr(window, "user_vars", {}).get("worktree_role") == "shell":
            return window
    for window in windows:
        if not window.has_running_program:
            return window
    return None


def handle_result(args, answer, target_window_id, boss):
    tab = boss.active_tab
    if tab is None:
        return

    # Matched within the tab rather than with `--match var:…`, which would
    # reach every tagged pane in every tab and type into all of them.
    shell = shell_pane(tab)
    if shell is None or shell.has_running_program:
        return

    boss.call_remote_control(shell, ("focus-window", "--match", "id:%d" % shell.id))

    # Ctrl-U first, so a half-typed command does not get this appended to it
    # and run as one line. zsh's emacs keymap binds it to kill-whole-line,
    # which puts the text on the kill ring, so Ctrl-Y brings it back.
    boss.call_remote_control(
        shell, ("send-text", "--match", "id:%d" % shell.id, "\x15wt switch\n")
    )


handle_result.no_ui = True
