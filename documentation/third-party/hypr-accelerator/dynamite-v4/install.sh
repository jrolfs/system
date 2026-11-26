#!/usr/bin/env bash
# Installer for the portable Quickshell shell bundle.
# Run it on the target machine:  ./install.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"

say()  { printf '\033[1;36m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

# 1) dependencies (Arch + an AUR helper)
if   command -v paru >/dev/null 2>&1; then AUR=paru
elif command -v yay  >/dev/null 2>&1; then AUR=yay
else AUR=""; fi

if [ -n "$AUR" ] && [ -f "$HERE/packages.txt" ]; then
    mapfile -t pkgs < <(grep -vE '^\s*#|^\s*$' "$HERE/packages.txt" | awk '{print $1}')
    say "Installing ${#pkgs[@]} packages with $AUR ..."
    "$AUR" -S --needed "${pkgs[@]}" || warn "Some packages failed. Install them by hand (see packages.txt)."
else
    warn "No paru/yay found (or not on Arch). Install the deps in packages.txt yourself."
    warn "Copying the config files anyway."
fi

# 2) back up whatever's already there, then copy ours in
backup() { [ -e "$1" ] && { mv "$1" "$1.bak.$(date +%s)"; warn "backed up existing $1"; }; }
mkdir -p "$CFG"
backup "$CFG/quickshell"
backup "$CFG/wallust"
cp -r "$HERE/config/quickshell" "$CFG/quickshell"
cp -r "$HERE/config/wallust"    "$CFG/wallust"
chmod +x "$CFG/wallust/"*.sh 2>/dev/null || true
say "Installed to $CFG/quickshell and $CFG/wallust"

# 3) empty wallpaper folder per theme, so the picker has somewhere to look
for j in "$CFG"/wallust/colorschemes/*.json; do
    [ -e "$j" ] || continue
    mkdir -p "$CFG/colorschemes/$(basename "$j" .json)/wallpapers"
done
say "Made empty wallpaper folders under $CFG/colorschemes/<theme>/wallpapers/"

cat <<EOF

Done. Next steps (details in README.md):
  1. Add the keybinds and 'exec-once = qs' to your Hyprland config.
  2. Disable any other polkit agent (polkit-gnome, polkit-kde, ...) so this one registers.
  3. Fonts: install SF Pro Text / SF Pro Display for the exact look, or pick fonts
     you've got in Settings -> Appearance (they're config.json's fontBody / fontDisplay).
  4. Drop wallpapers into ~/.config/colorschemes/<theme>/wallpapers/.
  5. Start it:  qs        (run it in a terminal first so you can watch for errors)
EOF
