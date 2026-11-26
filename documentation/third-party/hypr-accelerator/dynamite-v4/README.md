# Quickshell desktop shell, portable bundle

A whole custom desktop shell written in QML on [Quickshell](https://quickshell.org) for
**Hyprland** (Wayland): a dynamic-island status bar that morphs in place into a launcher,
control center, notifications, OSDs, power menu, lock screen, polkit agent, theme/wallpaper
pickers, settings, and a calendar.

This is the **shell-only** bundle: the Quickshell config plus the `wallust` theme engine. It
does not include wallpapers or a full Hyprland config, so you keep your own Hyprland setup and
just add a few keybinds.

## Requirements

- **Hyprland** on Wayland, on an **Arch-based** distro with an AUR helper (`paru`/`yay`).
- Quickshell **0.3.0+** (`quickshell-git`).

## Install

```bash
./install.sh
```

It installs the packages in `packages.txt`, backs up any existing `~/.config/quickshell` and
`~/.config/wallust` (to `*.bak.<timestamp>`), copies the new ones in, and makes empty
per-theme wallpaper folders. Then do the manual steps below.

## 1. Hyprland keybinds + autostart

Add these to your Hyprland config (hyprland.conf syntax, pick whatever keys you like):

```ini
exec-once = qs

# panels (the shell registers these as GlobalShortcuts)
bind  = SUPER,        Space,  global, quickshell:launcher
bind  = SUPER,        T,      global, quickshell:theme
bind  = SUPER SHIFT,  T,      global, quickshell:wallpaper
bind  = SUPER,        comma,  global, quickshell:settings
bind  = SUPER,        C,      global, quickshell:calendar
bind  = CTRL ALT,     Delete, global, quickshell:logout
bind  = CTRL ALT,     L,      global, quickshell:lock
bind  = SUPER,        N,      global, quickshell:nightlight
bind  = SUPER,        G,      global, quickshell:gamemode

# control center has no GlobalShortcut, so bind it (the island's pill also opens it):
bind  = SUPER,        A,      exec,   qs ipc call controlcenter toggle

# brightness + volume (in-process, smooth on key-repeat, so use the repeating variant)
bindle = , XF86MonBrightnessUp,   global, quickshell:brightnessUp
bindle = , XF86MonBrightnessDown, global, quickshell:brightnessDown
bindle = , XF86AudioRaiseVolume,  global, quickshell:volumeUp
bindle = , XF86AudioLowerVolume,  global, quickshell:volumeDown
bind   = , XF86AudioMute,         global, quickshell:volumeMute
```

> On a **Lua** Hyprland config instead? Each bind is
> `hl.bind("<keys>", hl.dsp.global("quickshell:<name>"))`, and `exec-once` is
> `hl.exec_once("qs")` (or however your config autostarts things).

Anything with a GlobalShortcut also works over IPC for testing:
`qs ipc call <target> toggle` (targets: `launcher`, `controlcenter`, `theme`, `wallpaper`,
`settings`, `calendar`, `logout`, `lock`, `nightlight`, `gamemode`).

## 2. Fonts (the one thing that won't look identical out of the box)

The shell asks for **SF Pro Text** and **SF Pro Display** (Apple fonts, not redistributable,
so they're not bundled) plus **JetBrainsMono Nerd Font** (which `install.sh` does install).
For the exact look, install the SF fonts yourself. Otherwise change them in
**Settings → Appearance** — no file editing needed.

They live in `config.json` if you'd rather set them there:

```json
"fontDisplay": "JetBrains Mono",
"fontBody": "Inter"
```

Any installed sans/mono works, and the change hot-reloads live. (`Theme.qml` only reads
these through `Config`, so don't edit the font lines there — they're not the values.)

## 3. Polkit agent

Only one polkit agent runs per session. Disable any other one (`hyprpolkitagent`,
`polkit-gnome`, `polkit-kde-agent`, `lxqt-policykit`, `mate-polkit`): remove it from autostart
and re-login. Otherwise the shell's auth prompt never shows up.

## 4. Theming

The 18 palettes live in `~/.config/wallust/colorschemes/`. The theme switcher (SUPER+T) runs
`~/.config/wallust/theme-apply.sh <name>`, which writes `~/.config/quickshell/colors.json` via
`wallust`; `Theme.qml` watches that file and restyles live, no restart. If `colors.json`
isn't there, the shell falls back to the built-in Ariadne palette.

`theme-apply.sh` also tries to recolor other apps (kitty, GTK, and so on). Those steps are
best-effort and simply do nothing on a machine that doesn't have those apps.

## 5. Wallpapers

Not included. Drop images into `~/.config/colorschemes/<theme>/wallpapers/`; the picker
(SUPER+Shift+T) reads the current theme's folder.

## Notes / gotchas

- **Multi-monitor** is handled for you; morphs, OSDs, and notifications appear on the focused
  monitor.
- **Lock screen** authenticates via PAM service `su` (which rejects wrong passwords correctly
  on a standard `pam_unix` setup). Keep a TTY escape handy the first time you test it
  (`Ctrl+Alt+F2`, then `loginctl unlock-sessions`).
- **Live-reload caveat:** value/token edits hot-reload, but structural edits (new widgets,
  changed models) often don't. Run `qs kill` and relaunch to be sure.
- Run `qs` in a foreground terminal while you set things up. QML errors print as
  `file.qml[line:col]: message`.
