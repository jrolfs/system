import os
import re

from kitty.tab_bar import DrawData, ExtraData, Formatter, TabBarData, draw_tab_with_powerline, as_rgb
from kitty.fast_data_types import Screen, get_boss
from kitty.utils import path_from_osc7_url
from kittens.ssh.utils import get_connection_data

SSH_BG = 0xEA6962  # gruvbox material red
SSH_ICON = "󰌘"
# Mirrors _ktt_max_title_len and its truncation glyph in zsh/kitty-tabs.zsh.
MAX_TITLE_LEN = 24
TRUNCATION_GLYPH = ""
COMBINING_RING = "̊"

# The ctrl+s>shift+N goto_session bindings in bindings.conf.
SESSION_NUMBERS = {"dotfiles": 1, "work": 2, "personal": 3}

REMOTE_HOME = re.compile(r"^/(?:Users|home)/[^/]+/?$|^/root/?$")


def ssh_window(tab_id: int):
    live_tab = get_boss().tab_for_id(tab_id)
    if not live_tab:
        return None
    windows = [window for window in live_tab if window.ssh_kitten_cmdline()]
    if not windows:
        return None
    return live_tab.active_window if live_tab.active_window in windows else windows[0]


def remote_dir_title(path: str) -> str:
    # The remote filesystem is out of reach from here, so the project icon and
    # worktree shortening in kitty-tabs.zsh can't be reproduced. The %1~ naming
    # and the length cap can, with the home directory guessed from its shape.
    if not path:
        return ""
    title = "~" if REMOTE_HOME.match(path) else os.path.basename(path.rstrip("/")) or "/"
    if len(title) > MAX_TITLE_LEN:
        title = title[: MAX_TITLE_LEN - 1] + TRUNCATION_GLYPH
    return title


def ssh_title(window) -> str:
    # The shell integration that kitten ssh installs remotely reports the cwd
    # as an OSC 7 URL carrying the remote hostname. Before the first prompt
    # there is none yet, so the host comes from the kitten's command line.
    url = window.screen.last_reported_cwd
    if isinstance(url, bytes):
        url = url.decode("utf-8", "replace")
    host = url.split("/")[2] if url and "://" in url else ""
    if not host:
        connection = get_connection_data(window.ssh_kitten_cmdline())
        host = connection.hostname if connection else ""
    host = host.split("@")[-1].split(".")[0].lower()
    path = path_from_osc7_url(url) if url else ""
    return f"{SSH_ICON} {Formatter.bold}{host}:{Formatter.nobold}{remote_dir_title(path)}"


def as_ssh_tab(tab: TabBarData | None) -> TabBarData | None:
    if tab is None:
        return None
    window = ssh_window(tab.tab_id)
    if window is None:
        return tab
    tab = tab._replace(title=ssh_title(window))
    tab = tab._replace(active_bg=SSH_BG, inactive_bg=SSH_BG)

    return tab


def draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_tab_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    original = tab
    tab = as_ssh_tab(tab)
    if tab is not original:
        draw_data = draw_data._replace(
            title_template=draw_data.title_template.replace("{index}", "{sub.index}" + COMBINING_RING),
        )
    # Each powerline slant is filled with the next tab's background, so that
    # tab needs the same treatment or the edge into an ssh tab stays uncoloured.
    # ExtraData is a plain class rather than a dataclass, so copy it by hand.
    next_extra_data = ExtraData()
    next_extra_data.prev_tab = extra_data.prev_tab
    next_extra_data.next_tab = as_ssh_tab(extra_data.next_tab)
    next_extra_data.for_layout = extra_data.for_layout
    extra_data = next_extra_data

    end = draw_tab_with_powerline(
        draw_data, screen, tab, before, max_tab_length, index, is_last, extra_data,
    )

    if is_last and tab.active_session_name:
        session_number = SESSION_NUMBERS.get(tab.active_session_name)
        session_label = f"   {session_number}  "
        label_len = len(session_label)
        cells_available = screen.columns - end

        if cells_available >= label_len:
            # Draw right-aligned session indicator
            padding = cells_available - label_len
            screen.cursor.x = end + padding
            screen.cursor.bg = as_rgb(0xAB6C7D)  # gruvbox dim purple
            screen.cursor.fg = as_rgb(0x282828)   # gruvbox bg dark
            screen.cursor.bold = True
            screen.draw(session_label)

    return end
