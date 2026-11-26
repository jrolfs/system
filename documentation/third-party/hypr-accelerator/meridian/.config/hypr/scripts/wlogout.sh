#!/usr/bin/env bash
set -Eeuo pipefail

A_1080=400
B_1080=400

# If wlogout already running, kill & exit
if pgrep -x "wlogout" >/dev/null 2>&1; then
  pkill -x "wlogout"
  exit 0
fi

# Pull monitor JSON once
mon_json="$(hyprctl -j monitors)"

# Focused monitor (fallback to first if none focused)
height="$(printf '%s' "$mon_json" | jq -r '(map(select(.focused==true))[0] // .[0]) | .height')"
scale="$(printf '%s' "$mon_json" | jq -r '(map(select(.focused==true))[0] // .[0]) | .scale')"

# Sanity checks
if [ -z "${height:-}" ] || [ -z "${scale:-}" ] || [ "$height" = "null" ] || [ "$scale" = "null" ]; then
  echo "Could not determine monitor height/scale." >&2
  exit 1
fi

# Compute logical resolution (height / scale), and scaled T/B based on 1080p baseline
# Formula keeps your original intent: X = X_1080 * 1080 * scale / (height/scale) = X_1080 * (1080 * scale^2 / height)
read -r Tpx Bpx <<EOF
$(awk -v a="$A_1080" -v b="$B_1080" -v h="$height" -v s="$scale" \
'BEGIN {
  if (h <= 0) { exit 1 }
  printf "%.0f %.0f", a*(1080*s*s/h), b*(1080*s*s/h)
}')
EOF

# Final guardrails
if [ -z "${Tpx:-}" ] || [ -z "${Bpx:-}" ]; then
  echo "Failed to compute T/B values." >&2
  exit 1
fi

# Launch wlogout
wlogout \
  -C "$HOME/.config/wlogout/theme.css" \
  -l "$HOME/.config/wlogout/layout" \
  --protocol layer-shell \
  -b 5 \
  -T "$Tpx" \
  -B "$Bpx" &

