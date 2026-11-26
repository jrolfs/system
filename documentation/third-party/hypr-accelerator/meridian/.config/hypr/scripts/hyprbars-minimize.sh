#!/usr/bin/env bash
# Toggle the focused window between the special workspace and the last normal one.

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr_last_normal_ws"

# Which workspace is the focused window on?
win_ws="$(hyprctl -j activewindow 2>/dev/null | jq -r '.workspace.name // empty')"

# If the focused window is NOT on a special workspace, remember current normal ws and send it to special (and show it).
if [[ "$win_ws" != special* ]]; then
  curr_id="$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.id')"
  [[ -n "$curr_id" ]] && printf '%s\n' "$curr_id" > "$STATE_FILE"
  hyprctl dispatch movetoworkspacesilent special
  exit 0
fi

# If the focused window IS on special, send it back to the last normal ws (default 1).
target_ws="1"
if [[ -f "$STATE_FILE" ]]; then
  read -r target_ws < "$STATE_FILE"
fi

hyprctl dispatch movetoworkspace "$target_ws"

