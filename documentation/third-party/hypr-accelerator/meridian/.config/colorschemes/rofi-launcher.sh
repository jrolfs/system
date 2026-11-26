#!/bin/bash

THEME_DIR="$HOME/.config/colorschemes"
APPLY_SCRIPT="$THEME_DIR/apply-theme.sh"

# List only non-hidden directories
themes=($(find "$THEME_DIR" -mindepth 1 -maxdepth 1 -type d ! -iname ".*" -exec basename {} \; | sort))

# Show menu
selected=$(printf '%s\n' "${themes[@]}" | rofi -dmenu -p "Select Theme" -theme ~/.config/colorschemes/rofi-theme.rasi)

# Apply selected theme if not empty
[[ -n "$selected" ]] && "$APPLY_SCRIPT" "$selected" >/dev/null 2>&1
