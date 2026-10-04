#!/usr/bin/env zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Arrange 📲
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🖥️
# @raycast.packageName Sidecar
# @raycast.argument1 { "type": "dropdown", "placeholder": "Side", "data": [{ "title": "Left", "value": "left" }, { "title": "Right", "value": "right" }, { "title": "Top", "value": "top" }, { "title": "Bottom", "value": "bottom" }] }
# @raycast.argument2 { "type": "dropdown", "placeholder": "Align", "optional": true, "data": [{ "title": "Start", "value": "start" }, { "title": "Center", "value": "center" }, { "title": "End", "value": "end" }] }

# Places the "Leto" Sidecar display flush against a side of the main screen via
# the `sidecar` CLI. `connect --arrange=<side>` is idempotent: it connects first
# if needed, then arranges — so this works whether or not Leto is connected.

# Ensure the nix system profile (where `sidecar` lives) is on PATH regardless of
# how Raycast invokes the script.
export PATH="/run/current-system/sw/bin:$PATH"

side="$1"
align="$2"

# `--arrange-align` runs along the axis perpendicular to the side, so the useful
# default differs by side: bottom edges level when Leto sits beside the laptop,
# horizontally centered when it sits above or below.
case "$side" in
  left | right) align="${align:-end}" ;;
  top | bottom) align="${align:-center}" ;;
  *)
    echo "Unknown side: ${side}"
    exit 1
    ;;
esac

if output=$(sidecar connect "Leto" --arrange="$side" --arrange-align="$align" 2>&1); then
  echo "Leto arranged ${side} (align: ${align})"
else
  echo "Sidecar error: ${output}"
fi
