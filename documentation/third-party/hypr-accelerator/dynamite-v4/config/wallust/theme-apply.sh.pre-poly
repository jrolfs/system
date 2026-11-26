#!/usr/bin/env bash
# Apply a curated wallust colorscheme by name (or path) and reload every app.
#
# wallust `cs` writes templates but does NOT run [hooks] (only `run` does), so the
# reloads are performed here. Quickshell needs no reload, Theme.qml reads
# colors.json via a watched FileView and restyles live.
#
# GTK is OPTION B: the hand-made custom GTK 3/4 themes are preserved and switched
# from ~/.config/colorschemes/<name>/ (symlink the per-theme gtk-4.0 + set the GTK
# theme name), GTK is NOT recolored by wallust templates.
#
# Usage: theme-apply.sh <name|/path/to/scheme.json>
#   names resolve to ~/.config/wallust/colorschemes/<name>.json

set -uo pipefail
arg="${1:?usage: theme-apply.sh <name|scheme.json>}"

scheme="$arg"
[ -f "$scheme" ] || scheme="$HOME/.config/wallust/colorschemes/${arg}.json"
if [ ! -f "$scheme" ]; then
    notify-send "Theme" "No colorscheme: $arg" -u critical 2>/dev/null || true
    echo "no colorscheme: $arg" >&2
    exit 1
fi
name="$(basename "$scheme" .json)"

wallust cs "$scheme" -s || { echo "wallust cs failed" >&2; exit 1; }

# --- sync the shell's Config (theme) + auto-apply this theme's last-used wallpaper ---
# Keeps config.json in sync regardless of entry point (CLI or in-shell switcher),
# and restores the wallpaper last chosen for this theme (else its first one).
cfg="$HOME/.config/quickshell/config.json"
state="$HOME/.config/quickshell/wallpaper-state"
wpdir="$HOME/.config/colorschemes/$name/wallpapers"
wp=""
[ -f "$state" ] && wp="$(awk -F'\t' -v t="$name" '$1==t{print $2; exit}' "$state")"
if [ -z "$wp" ] || [ ! -f "$wp" ]; then
    wp="$(find "$wpdir" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | sort | head -1)"
fi
# Write the theme (and this theme's wallpaper, if we found one) into config.json with
# python3, NOT jq. jq isn't guaranteed to be installed, and when it went missing this
# silently no-op'd, so the theme switcher looked dead. python3 is basically always there.
# Single writer: the in-shell switcher no longer touches config.json, so no write race.
if command -v python3 >/dev/null 2>&1 && [ -f "$cfg" ]; then
    if python3 - "$cfg" "$name" "$wp" <<'PY'
import json, os, sys
cfg, name, wp = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    d = json.load(open(cfg))
except Exception:
    d = {}
d["theme"] = name
if wp and os.path.isfile(wp):
    d["wallpaper"] = wp
tmp = cfg + ".tmp"
with open(tmp, "w") as f:
    json.dump(d, f, indent=4)
os.replace(tmp, cfg)   # atomic
PY
    then
        if [ -n "$wp" ] && [ -f "$wp" ]; then
            "$HOME/.config/wallust/wallpaper-record.sh" "$name" "$wp" 2>/dev/null || true
        fi
    fi
fi

# --- non-GTK reloads (cs skips wallust [hooks]) ---
hyprctl reload    >/dev/null 2>&1 || true
pkill -USR1 kitty 2>/dev/null      || true
# foot: new windows pick up colors. vesktop: hot-reloads CSS. quickshell: live FileView.

# --- GTK (option B): switch the matching custom GTK 3/4 theme, if one exists ---
csdir="$HOME/.config/colorschemes/$name"
if [ -d "$csdir/gtk-4.0" ]; then
    ln -sf  "$csdir/gtk-4.0/gtk.css"      "$HOME/.config/gtk-4.0/gtk.css"      2>/dev/null || true
    ln -sf  "$csdir/gtk-4.0/gtk-dark.css" "$HOME/.config/gtk-4.0/gtk-dark.css" 2>/dev/null || true
    [ -e "$csdir/gtk-4.0/assets" ] && ln -sfn "$csdir/gtk-4.0/assets" "$HOME/.config/gtk-4.0/assets" 2>/dev/null || true
fi
if [ -f "$csdir/gtk-theme" ]; then
    gsettings set org.gnome.desktop.interface gtk-theme "$(cat "$csdir/gtk-theme")" 2>/dev/null || true
fi

# --- spicetify (option B: curated Sleek color schemes; best-effort name match) ---
if command -v spicetify >/dev/null 2>&1; then
    sptheme="$(spicetify config current_theme 2>/dev/null)"
    ini="$HOME/.config/spicetify/Themes/${sptheme}/color.ini"
    for cand in "$name" "${name}-dark"; do
        if [ -f "$ini" ] && grep -q "^\[${cand}\]" "$ini"; then
            spicetify config color_scheme "$cand" >/dev/null 2>&1 || true
            spicetify refresh                     >/dev/null 2>&1 || true
            break
        fi
    done
fi

# --- nvim / NvChad (option B): patch the theme name in the live chadrc ---
nvchadrc="$HOME/.config/nvim/lua/chadrc.lua"
if [ -f "$csdir/nvim/lua/chadrc.lua" ] && [ -f "$nvchadrc" ]; then
    nvtheme="$(grep -oP 'theme\s*=\s*"\K[^"]+' "$csdir/nvim/lua/chadrc.lua" 2>/dev/null | head -1)"
    [ -n "$nvtheme" ] && sed -i "s/theme = \"[^\"]*\"/theme = \"$nvtheme\"/" "$nvchadrc" 2>/dev/null || true
fi

# --- vscodium (option B): set workbench.colorTheme to the named extension theme ---
vscfg="$HOME/.config/VSCodium/User/settings.json"
if [ -f "$csdir/vscodium-theme" ] && [ -f "$vscfg" ] && command -v jq >/dev/null 2>&1; then
    vsname="$(cat "$csdir/vscodium-theme")"
    tmp="$(mktemp)"
    if jq --arg t "$vsname" '.["workbench.colorTheme"]=$t' "$vscfg" >"$tmp" 2>/dev/null; then
        mv "$tmp" "$vscfg"
    else
        rm -f "$tmp"
    fi
fi

