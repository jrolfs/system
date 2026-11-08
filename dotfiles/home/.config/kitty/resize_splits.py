#!/usr/bin/env python

"""Grow, shrink or equalize the splits in the active tab, animated.

kitty's resize_window and `layout_action equalize` jump straight to the new
sizes. Here the split biases step toward their targets on a timer instead,
the way kitty's own mouse drag-resize moves a divider: every pane in the tab
has its resize notifications paused for the duration, so the program in each
one gets a single SIGWINCH with the final size rather than one per frame.

`grow` and `shrink` scale the active pane by SCALE along both axes, keeping
its aspect ratio. An axis the pane already spans edge to edge has nothing to
take space from, so only the other one changes.
"""

from time import monotonic

from kitty.fast_data_types import add_timer, remove_timer

SCALE = 1.3
DURATION = 0.15
FRAME_INTERVAL = 1 / 60

# The pane on the other side of a split never gets less than this share of
# it. Squeezing a shell down to a few columns rewraps its scrollback at that
# width, and every line past scrollback_lines is gone for good.
MIN_SHARE = 0.1

# On the tab rather than in a module global, because kitty executes a custom
# kitten afresh on every keypress.
STATE_ATTRIBUTE = "_resize_splits_animation"


def main():
    pass


def scale_axis(path, horizontal, factor):
    """Scale the pane's share along one axis, nearest split first.

    When the nearest split runs out of room the rest of the factor comes from
    the next split up on the same axis, so the pane keeps growing at the
    expense of panes further away.
    """
    growing = factor > 1
    for pair, in_one in reversed(path):
        if pair.horizontal != horizontal or pair.is_redundant:
            continue
        share = pair.bias if in_one else 1 - pair.bias
        wanted = share * factor
        # Never move against the requested direction, which clamping alone
        # would do to a share that a drag already took past the limits.
        if growing:
            new_share = max(share, min(wanted, 1 - MIN_SHARE))
        else:
            new_share = min(share, max(wanted, MIN_SHARE))
        pair.bias = new_share if in_one else 1 - new_share
        factor = wanted / new_share
        if abs(factor - 1) < 1e-6:
            return


def scale_active_pane(factor):
    def change(layout, tab):
        group = tab.windows.active_group
        if group is None:
            return
        path = layout.pairs_root.find_window_in_tree(group.id)
        if path is None:
            return
        scale_axis(path, True, factor)
        scale_axis(path, False, factor)

    return change


def equalize(layout, tab):
    layout.equalize_biases()


CHANGES = {
    "grow": scale_active_pane(SCALE),
    "shrink": scale_active_pane(1 / SCALE),
    "equalize": equalize,
}


class Animation:
    def __init__(self, pairs, starts, targets):
        self.pairs = pairs
        self.starts = starts
        self.targets = targets
        self.started_at = monotonic()
        self.timer_id = 0


def set_biases(pairs, biases):
    for pair, bias in zip(pairs, biases):
        pair.bias = bias


def finish(boss, tab, animation):
    set_biases(animation.pairs, animation.targets)
    if getattr(tab, STATE_ATTRIBUTE, None) is animation:
        delattr(tab, STATE_ATTRIBUTE)
    if boss.tab_for_id(tab.id) is not tab:
        return
    tab.relayout()
    for window in tab:
        window.pause_resize_notifications_to_child(False)
    # kitty only queues a paused pane's size when it differs from the last one
    # reported, so a pane that moved mid-animation and ended where it started
    # still has an intermediate size queued, and unpausing reports that. This
    # second pass sees the mismatch and sends the real size.
    tab.relayout()


def animate(boss, tab, change):
    layout = tab.current_layout
    pairs = tuple(layout.pairs_root.self_and_descendants())
    current = [pair.bias for pair in pairs]

    previous = getattr(tab, STATE_ATTRIBUTE, None)
    if previous is not None:
        remove_timer(previous.timer_id)
        # Start from where the running animation was headed, so a second
        # press mid-flight scales the size the first one was going to reach
        # rather than whatever frame happened to be on screen.
        set_biases(previous.pairs, previous.targets)

    change(layout, tab)
    targets = [pair.bias for pair in pairs]
    set_biases(pairs, current)
    if previous is None and targets == current:
        return

    animation = Animation(pairs, current, targets)
    setattr(tab, STATE_ATTRIBUTE, animation)
    if previous is None:
        for window in tab:
            window.pause_resize_notifications_to_child()

    # One-shot timers, each frame scheduling the next. Removing a repeating
    # timer from inside its own callback would release the function that is
    # still running, where a one-shot one is removed by kitty after it returns.
    def step(timer_id):
        if boss.tab_for_id(tab.id) is not tab or tab.current_layout is not layout:
            finish(boss, tab, animation)
            return
        progress = min((monotonic() - animation.started_at) / DURATION, 1)
        if progress >= 1:
            finish(boss, tab, animation)
            return
        eased = 1 - (1 - progress) ** 3
        set_biases(
            pairs,
            [
                start + (target - start) * eased
                for start, target in zip(current, targets)
            ],
        )
        tab.relayout()
        animation.timer_id = add_timer(step, FRAME_INTERVAL, False)

    animation.timer_id = add_timer(step, FRAME_INTERVAL, False)


def handle_result(args, answer, target_window_id, boss):
    change = CHANGES.get(args[1] if len(args) > 1 else "")
    tab = boss.active_tab
    if change is None or tab is None or tab.current_layout.name != "splits":
        return
    animate(boss, tab, change)


handle_result.no_ui = True
