#!/usr/bin/env python3
"""Point a kitty tab's editor and shell panes at a different git worktree.

Installed as a worktrunk `post-switch` hook, so running `wt switch` in the
shell pane carries the rest of the tab along with it rather than leaving
neovim editing the worktree you just left.

Panes are named by a `worktree_role` user variable, set on the `launch` lines
in sessions/dotfiles.kitty-session, and an untagged tab falls back to working
the roles out from what each pane is running. Either way only `editor` and
`shell` move. The Claude pane spans worktrees by way of its background tasks,
so following the switch would cut it off from work it is still doing.

Nothing here is conditional on the repository, because nothing needs to be: a
tab whose panes yield no roles, and a shell outside kitty, both come out as a
silent no-op. That is what makes the hook safe to install globally.
"""

import glob
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

LUA = Path(__file__).resolve().parent / "session.lua"

# `kitten @` is the remote control client; the `kitty` launcher beside it
# starts a whole terminal. The homebrew symlink points into a versioned
# Caskroom directory, so the app bundle is the fallback that survives a cask
# upgrade landing mid-switch.
KITTEN = shutil.which("kitten") or "/Applications/kitty.app/Contents/MacOS/kitten"

# Everything a login shell might report as its command, with the leading dash
# of an argv[0] login marker already stripped.
SHELLS = {"zsh", "bash", "sh", "fish"}

# kitty-tabs.zsh caps automatic titles here, and matching it keeps a switched
# tab the same width as one titled by the shell.
MAX_TITLE = 24


def kitten(*arguments):
    """Run a `kitten @` remote control command against the current kitty."""
    return subprocess.run(
        [KITTEN, "@", *arguments],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )


def windows():
    listing = kitten("ls")
    if listing.returncode != 0:
        return None
    return json.loads(listing.stdout)


def tab_containing(tree, window_id):
    for os_window in tree:
        for tab in os_window["tabs"]:
            if any(window["id"] == window_id for window in tab["windows"]):
                return tab
    return None


def tagged_roles(tab):
    return {
        window["user_vars"]["worktree_role"]: window
        for window in tab["windows"]
        if window.get("user_vars", {}).get("worktree_role")
    }


def idle(window):
    """Whether a pane is sitting at a shell prompt with nothing running."""
    processes = window.get("foreground_processes", [])
    if len(processes) != 1:
        return False
    cmdline = processes[0].get("cmdline") or []
    if not cmdline:
        return False
    return os.path.basename(cmdline[0]).lstrip("-") in SHELLS


def inferred_roles(tab, invoking_id):
    """Work out the roles of an untagged tab from what its panes are running.

    Panes only carry `worktree_role` from the session file, so a tab that was
    open before this landed, or one split by hand, would otherwise need its
    panes recreated to take part. That would mean killing the Claude pane the
    whole arrangement exists to preserve.

    Nothing is assigned by elimination: the editor has to be running neovim
    and the shell has to be a bare shell at a prompt, so a pane running
    anything else, `claude` included, is simply not in the result. Tags are
    still worth having, because a pane busy with a command cannot be
    recognised this way and drops out of the switch for that run.

    An editor is required before any of it counts, which keeps this to tabs
    laid out like the ones in the session file. Without that, a tab that is
    just two shells side by side (frontends, api) would start having its
    second pane cd'd by a switch in the first, which nobody asked for.
    """
    found = {}
    shells = []
    for window in tab["windows"]:
        processes = window.get("foreground_processes", [])
        names = [
            os.path.basename((process.get("cmdline") or [""])[0])
            for process in processes
        ]
        if "editor" not in found and any(name == "nvim" for name in names):
            found["editor"] = window
        elif idle(window):
            shells.append(window)

    # The caller is cd'd by worktrunk already, so with more than one idle
    # shell in the tab it is the least useful of them to pick.
    for window in shells:
        if window["id"] != invoking_id:
            found["shell"] = window
            break
    else:
        if shells:
            found["shell"] = shells[0]

    return found if "editor" in found else {}


def descendants(pids, depth=2):
    """`pids` plus everything under them, to `depth` generations."""
    seen = set(pids)
    frontier = list(pids)
    for _ in range(depth):
        if not frontier:
            break
        listing = subprocess.run(
            ["pgrep", "-P", ",".join(str(pid) for pid in frontier)],
            capture_output=True,
            text=True,
            check=False,
        )
        frontier = [int(line) for line in listing.stdout.split() if int(line) not in seen]
        seen.update(frontier)
    return seen


def nvim_socket(window):
    """Locate the neovim server socket belonging to a kitty pane.

    Returns the socket path, or None when the pane is not running neovim.
    """
    # neovim 0.12 runs the TUI as the foreground process and the editor itself
    # as an `--embed` child, and it is the child's pid that names the socket.
    # So the pid kitty reports for the pane never matches on its own. Two
    # generations rather than one, in case the pane's shell did not exec away.
    pids = [process["pid"] for process in window.get("foreground_processes", [])]
    candidates = descendants(pids)

    # stdpath('run'), which is $XDG_RUNTIME_DIR when set and $TMPDIR/nvim.$USER
    # otherwise. On macOS there is no XDG_RUNTIME_DIR and TMPDIR is the
    # per-user directory under /var/folders, not /tmp.
    runtime = os.environ.get("XDG_RUNTIME_DIR") or os.path.join(
        tempfile.gettempdir(), "nvim.%s" % os.environ.get("USER", "")
    )
    for socket in glob.glob(os.path.join(runtime, "*", "nvim.*.0")):
        try:
            pid = int(os.path.basename(socket).split(".")[1])
        except (IndexError, ValueError):
            continue
        if pid in candidates:
            return socket
    return None


def vim_string(value):
    return "'" + value.replace("'", "''") + "'"


def move_editor(window, target):
    socket = nvim_socket(window)
    if socket is None:
        return "no neovim server"

    expression = "luaeval('loadfile(_A[1])().switch(_A[2])', [%s, %s])" % (
        vim_string(str(LUA)),
        vim_string(target),
    )
    try:
        result = subprocess.run(
            ["nvim", "--server", socket, "--remote-expr", expression],
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return "neovim did not answer"

    if result.returncode != 0:
        return (result.stderr or "neovim refused").strip().splitlines()[-1]
    return result.stdout.strip()


def move_shell(window, target):
    if not idle(window):
        return "busy, left alone"

    # Ctrl-U first, so a half-typed command does not get the cd appended to it
    # and run as one line. zsh's emacs keymap (prezto's default here) binds it
    # to kill-whole-line, which puts the text on the kill ring rather than
    # discarding it, so Ctrl-Y brings it back.
    #
    # send-text applies Python escaping to its argument, so a backslash in the
    # path has to survive one more round than shlex.quote accounts for.
    command = "cd %s" % shlex.quote(target).replace("\\", "\\\\")
    kitten("send-text", "--match", "id:%d" % window["id"], "\x15%s\n" % command)
    return "cd"


def short_name(path):
    """`…/system.kitty-raise` as `s.kitty-raise`, matching kitty-tabs.zsh.

    A worktree directory is named `<repo>.<branch>`, which spends most of a
    narrow tab on the repo name that every sibling tab also carries. The
    sibling check is what keeps it from firing on a directory that merely has
    a dot in its name.
    """
    name = os.path.basename(path)
    prefix, separator, rest = name.partition(".")
    if separator and os.path.isdir(os.path.join(os.path.dirname(path), prefix)):
        name = "%s.%s" % (prefix[0], rest.removeprefix("jamie-"))
    if len(name) > MAX_TITLE:
        name = name[: MAX_TITLE - 1] + "…"
    return name


def retitle(tab, target):
    # The icon is whatever the session file's `new_tab` line put in front of
    # the name. Reading it back off the tab keeps the glyph in one place
    # instead of repeating it here.
    title = tab.get("title", "")
    icon = ""
    head, separator, _ = title.partition(" ")
    if separator and head and not head.isascii():
        icon = head + " "
    kitten("set-tab-title", "--match", "id:%d" % tab["id"], icon + short_name(target))


def main(argv):
    if len(argv) != 2:
        print("usage: switch.py <worktree-path>", file=sys.stderr)
        return 2
    target = os.path.realpath(os.path.expanduser(argv[1]))
    if not os.path.isdir(target):
        print("switch.py: not a directory: %s" % target, file=sys.stderr)
        return 1

    # An agent creating a worktree to work in still fires post-switch, and
    # pulling the editor out from under whoever asked for it would be the
    # opposite of helpful. Claude Code's bash tool happens not to carry
    # KITTY_WINDOW_ID today, so this is belt and braces, but a `claude` running
    # in the agent pane with a fuller environment would otherwise qualify.
    if os.environ.get("CLAUDECODE"):
        return 0

    window_id = os.environ.get("KITTY_WINDOW_ID")
    if not window_id:
        return 0

    tree = windows()
    if tree is None:
        return 0
    tab = tab_containing(tree, int(window_id))
    if tab is None:
        return 0

    panes = tagged_roles(tab) or inferred_roles(tab, int(window_id))
    if not panes:
        return 0

    report = []
    if "editor" in panes:
        outcome = move_editor(panes["editor"], target)
        # A refusal has to stop the rest of the move. Carrying on would leave
        # the tab reading as the new worktree in the title and the shell while
        # the editor is still in the old one, which is worse than not moving:
        # the next `rg` in that shell searches a tree the open buffers are not
        # from. neovim says so itself as well, via vim.notify.
        if outcome.startswith("unsaved:"):
            print(
                "switch.py: neovim has %s unsaved buffer(s), tab left where it was"
                % outcome.partition(":")[2],
                file=sys.stderr,
            )
            return 1
        report.append("editor %s" % outcome)

    # The pane that ran `wt switch` is cd'd by worktrunk's own shell
    # integration, and is mid-command here in any case.
    if "shell" in panes and panes["shell"]["id"] != int(window_id):
        report.append("shell %s" % move_shell(panes["shell"], target))
    retitle(tab, target)

    if report:
        print("%s · %s" % (short_name(target), ", ".join(report)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
