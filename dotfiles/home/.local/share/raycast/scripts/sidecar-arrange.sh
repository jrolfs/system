#!/usr/bin/env zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Arrange 📲
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🖥️
# @raycast.packageName Sidecar
# @raycast.argument1 { "type": "dropdown", "placeholder": "Side", "data": [{ "title": "Left", "value": "left" }, { "title": "Right", "value": "right" }, { "title": "Top", "value": "top" }, { "title": "Bottom", "value": "bottom" }] }

# Places the "Leto" Sidecar display flush against a side of the main screen via
# the `sidecar` CLI. `connect --arrange=<side>` is idempotent: it connects first
# if needed, then arranges — so this works whether or not Leto is connected.

# Ensure the nix system profile (where `sidecar` lives) is on PATH regardless of
# how Raycast invokes the script.
export PATH="/run/current-system/sw/bin:$PATH"

side="$1"

case "$side" in
  left | right | top | bottom)
    if output=$(sidecar connect "Leto" --arrange="$side" 2>&1); then
      echo "Leto arranged ${side}"
    else
      echo "Sidecar error: ${output}"
    fi
    ;;
  *)
    echo "Unknown side: ${side}"
    ;;
esac
