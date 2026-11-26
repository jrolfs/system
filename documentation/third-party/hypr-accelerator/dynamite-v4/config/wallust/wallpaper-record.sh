#!/usr/bin/env bash
# Record the last-used wallpaper for a theme, in ~/.config/quickshell/wallpaper-state
# (one "theme<TAB>path" line per theme). Usage: wallpaper-record.sh <theme> <path>
set -uo pipefail
t="${1:?theme}"; p="${2:?path}"
state="$HOME/.config/quickshell/wallpaper-state"
mkdir -p "$(dirname "$state")"
tmp="$(mktemp)"
[ -f "$state" ] && grep -vP "^${t}\t" "$state" >"$tmp" 2>/dev/null || true
printf '%s\t%s\n' "$t" "$p" >>"$tmp"
mv "$tmp" "$state"
