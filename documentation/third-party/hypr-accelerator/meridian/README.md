# Welcome to Meridian!

**Meridian** is a comprehensive Hyprland environment with system-wide dynamic theming. Switch between Catppuccin, Everforest, Gruvbox, and more — watch your entire desktop adapt instantly.

Note:
- To ensure maximum success rate of installing the Meridian environment on your system, an install script has not been provided. Instead, detailed instructions have been given below that enable you to understand what's going on so you're able to troubleshoot if necessary. This is subject to change in the future. Thanks!

- Open this document with [Markdown Live Preview](https://markdownlivepreview.com/) or any Markdown previewer for the best experience.

## 1. Install dependencies

Use an AUR helper like `yay` or `paru` to install the following. Using `yay`:

```
yay -S --needed apple_cursor asciiquarium brightnessctl grim gtk4 hypridle hyprland hyprlock hyprpicker jq kitty kvantum kvantum-qt5 nwg-look otf-geist-mono-nerd pamixer playerctl polkit-gnome qt5ct qt6ct qt5-wayland qt6-wayland rofi rofi-calc slurp spicetify-cli spicetify-marketplace-bin spotify-adblock-git swaync swww thunar thunar-archive-plugin nautilus ttf-jetbrains-mono-nerd vesktop vscodium vscodium-marketplace waybar wl-clipboard wlogout wlsunset xdg-desktop-portal-hyprland xdg-desktop-portal-gtk zsh papirus-icon-theme papirus-folders
```

## 1.1. Install fonts

SF Pro Text is the font mainly used in all apps. Install it and the rest of the SF font family using a script I wrote:

```
git clone https://github.com/saneaspect/sf-fonts
cd sf-fonts/
bash install.sh
cd ..
rm -rf sf-fonts/
```

## 2. Copy configuration files

This is the part where you copy over the config files from this folder to the appropriate location in your home folder.

## 2.1. Shell

I'm using zsh with the ohmyzsh framework and powerlevel10k theme. If you want the prompt you see in all my videos, you can copy over the .z* files.

```
cp .zshrc ~/
cp .zprofile ~/
cp .p10k.zsh ~

cp -r .oh-my-zsh/ ~/
```

## 2.2. `.config`

Here's what each of the directories inside `~/.config` are for:

| Directory/File | Description |
|----------------|-------------|
| colorschemes | Custom theme switcher code |
| fontconfig | Font rendering optimization |
| gtk-3.0 | GTK3 config files |
| gtk-4.0 | GTK4 config files |
| hypr | Hyprland config files |
| kitty | Kitty terminal config files |
| kvantum | Controls theme of Qt5 and Qt6 apps |
| nvim | Neovim configuration |
| nwg-look | GTK3/4 configurator (same function as lxappearance) |
| qt5ct/qt6ct | Controls appearance of Qt5 and Qt6 apps (same function as gnome-tweaks, but for Qt apps) |
| rofi | Rofi app launcher config files |
| spicetify | Config files used to theme Spotify |
| swaync | Notification daemon and panel |
| vesktop | Config and theme files for a Discord variant |
| waybar | Status bar config files |
| wlogout | Config files for logout menu |
| spotify-flags.conf | Ensures Spotify opens in Wayland mode |

The next command will copy every single folder inside of `./.config` (in this directory) to `~/.config`. Make sure you back up any directories inside `~/.config` because they WILL be overwritten. If you want to copy only certain folders over, now's your chance.

```
cp -r .config/* ~/.config
```

## 2.3. `.local`

Inside `.local`, we have two folders: `bin` and `share`.

`bin` contains core scripts that make Meridian what it is, work; namely, the custom theme switcher, night mode and the Waybar layout switcher. I also added the fetch tool I use as a bonus :)

`share` contains another Rofi config and its themes.

Copy them over with the following command:

```
cp -r .local/bin ~/.local
cp -r .local/share/rofi ~/.local/share
```

## 2.4. `.themes`

This folder contains all the GTK themes necessary to make the custom theme switcher work. They're also really cool!

Copy them with the following command:

```
cp -r .themes/ ~/
```

^ This will overwrite any themes you already have inside `~/.themes` if you do, so be careful.

## 2.5. `.vscode-oss`

This folder contains all the extensions/themes for VSCodium (not VSCode). If you prefer, you can manually install these through the editor, or you can just copy it over.

```
mkdir -p ~/.vscode-oss/extensions

cp -r .vscode-oss/extensions/* ~/.vscode-oss/extensions/
```

## 3. Keybinds:
| Keybind | Action |
|---------|--------|
| **General** | |
| `ALT + K` | Kill active window |
| `ALT + W` | Close active window |
| `ALT + M` | Exit Hyprland |
| `ALT + F` | Toggle fullscreen |
| `ALT + V` | Toggle floating |
| `ALT + L` | Lock screen |
| **Applications** | |
| `ALT + Return` | Open Kitty terminal |
| `ALT + E` | Open Thunar file manager |
| `ALT + Shift + E` | Open Nautilus file manager |
| `ALT + D` | Open app launcher (Rofi) |
| `ALT + C` | Open calculator (Rofi) |
| `ALT + Shift + B` | Open Brave Browser |
| **Theming & Customization** | |
| `ALT + T` | Open theme switcher |
| `ALT + Shift + T` | Open wallpaper selector |
| `ALT + N` | Toggle night mode |
| `ALT + H` | Open color picker |
| `ALT + R` | Relaunch Waybar |
| `ALT + Shift + R` | Switch Waybar layout |
| `ALT + Y` | Load title bars plugin (requires hyprbars to be configured) |
| `ALT + Shift + Y` | Unload title bars plugin (requires hyprbars to be configured) |
| **Screenshots** | |
| `ALT + F12` | Take full screenshot |
| `ALT + Shift + F12` | Take regional screenshot |
| **System Controls** | |
| `ALT + A` | Toggle notification center |
| `ALT + Ctrl + Shift + A` | Reload notification daemon |
| `Ctrl + Alt + Delete` | Open logout menu |
| `F1` | Toggle mute |
| `F2` | Decrease volume |
| `F3` | Increase volume |
| `F5` | Decrease brightness |
| `F6` | Increase brightness |
| `F9` | Previous track |
| `F10` | Play/pause |
| `F11` | Next track |
| `Win + F1` | Toggle Blitz Mode |
| **Workspaces** | |
| `ALT + 1-9/0` | Switch to workspace 1-10 |
| `ALT + Shift + 1-9/0` | Move window to workspace 1-10 |
| `ALT + S` | Toggle scratchpad |
| `ALT + Shift + S` | Move window to scratchpad |
| `ALT + Mouse Wheel` | Cycle workspaces |
| **Window Management** | |
| `ALT + Arrow Keys` | Move focus |
| `ALT + Mouse Left Drag` | Move window |
| `ALT + Mouse Right Drag` | Resize window |
| `Ctrl + Alt + Arrow Keys` | Resize window |
| `Super + Shift + Arrow Keys` | Move window |
| `ALT + P` | Toggle pseudotile (Dwindle) |
| **Layout Switching** | |
| `ALT + J` | Switch to scrolling layout (requires hyprscrolling plugin) |
| `ALT + Shift + J` | Switch to master layout |
| **Master Layout** | |
| `Super + M` | Add master window |
| `Super + Shift + M` | Remove master window |
| `Super + H` | Decrease master factor |
| `Super + L` | Increase master factor |
| **Scrolling Layout** | |
| `Super + .` | Move view right (column) |
| `Super + ,` | Move view left (column) |
| `Super + Shift + .` | Move window right |
| `Super + Shift + ,` | Move window left |
| `Super + Shift + Up/Down` | Move window up/down |
| `Super + =` | Increase column width |
| `Super + -` | Decrease column width |
| `Super + C` | Cycle to next preset width |
| `Super + X` | Cycle to previous preset width |
| `Super + P` | Promote window to new column |
| `Super + F` | Toggle center vs fit |
| `Super + S` | Swap column right |
| `Super + A` | Swap column left |
| `Super + 1-3` | Move column to workspace 1-3 |
| **Zoom** | |
| `Super + Mouse Wheel` | Zoom in/out |
| `Super + =` | Zoom in |
| `Super + -` | Zoom out |
| `Super + Shift + 0` | Reset zoom |
| **OBS** | |
| `Ctrl + Super + R` | Start/stop recording (when OBS focused) |

## 4. Enjoy Meridian!

`reboot` to make sure all changes take effect.

