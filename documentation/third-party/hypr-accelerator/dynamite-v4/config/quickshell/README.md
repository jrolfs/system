# quickshell desktop

My whole desktop, written in QML on [Quickshell](https://quickshell.org) for Hyprland. No
C++, no waybar, no rofi, no swaync. One process draws a "dynamic island" status bar that
morphs in place into damn near everything: launcher, control center, notifications, OSDs,
power menu, lock screen, polkit prompt, theme and wallpaper pickers, settings, and a
calendar.

Fixin' to change how anything looks? Read `DESIGN.md` first. It's the visual and motion
language every surface follows, and freestyling it just makes stuff look off.

## the stack (matters more than you'd think)

- **Compositor:** Hyprland (Wayland). Workspaces, monitors, and keybinds go through
  `Quickshell.Hyprland` and `GlobalShortcut`; click-outside dismiss is `HyprlandFocusGrab`.
- **Distro:** Arch, so deps come from the AUR (`paru`/`yay`).
- **Quickshell:** 0.3.0 via `quickshell-git`. It builds from latest git, so it's sometimes
  ahead of the tagged docs. If an API doesn't match the docs, check the installed QML
  modules before you assume you're the one who's wrong.
- **Launch:** bare `qs` from Hyprland autostart. This is the top-level default config at
  `~/.config/quickshell/`, entry `shell.qml`. No named subfolder, 'cause a subfolder just
  gets shadowed by this top-level `shell.qml`. Don't make one.

## how to think about it

You don't configure Quickshell, you declare the whole shell in QML and it hot-reloads on
save. A few things that took me a minute to get:

- **Singletons are the architecture.** Shared state (audio, battery, theme, config, which
  panel's open) lives in `pragma Singleton` types: one global instance each, reactive,
  reachable by type name. That's how everything talks to everything. You can't reach an `id`
  across a file boundary, so pass data through `required property` inputs or read a singleton.
- **Multi-monitor ain't optional.** Top-level windows go in
  `Variants { model: Quickshell.screens }`, or the bar vanishes the second you unplug a
  monitor and never shows on the second one to begin with.
- **Heavy objects belong in singletons, never a per-screen delegate.** Drop a `Process` or
  `Timer` into a `Variants` delegate and congrats, now it runs once per monitor.
- **Windows:** `PanelWindow` for layer-shell stuff (bars, overlays, OSDs), `PopupWindow`
  anchored to another window, `WlSessionLock` for the locker (the only right way to do it).

## layout

```
~/.config/quickshell/
├── shell.qml          # entry: one Bar per screen, lazy-loads panels, registers shortcuts/IPC
├── config/            # Config (JsonAdapter -> config.json) + GlobalState (which panel's open)
├── theme/Theme.qml    # every design token: colors, fonts, radii, spacing, durations
├── services/          # one singleton per system concern (Audio, Battery, Network, ...)
├── modules/           # the UI surfaces: bar/ launcher/ controlcenter/ lock/ polkit/ ...
├── components/        # dumb reusable bits: StyledText, Slider, Toggle, Icon, ...
└── assets/            # icons, fonts
```

Everything's native-first. Audio (Pipewire), battery (UPower), media (MPRIS), tray, network,
bluetooth, notifications, PAM, polkit: all native bindings. The only things that shell out to
a `Process`, since 0.3 has no native binding for 'em, are screen brightness
(`brightnessctl`/`ddcutil`), clipboard history (`cliphist`), power/session past logout
(`loginctl`/`systemctl`), and poking Hyprland at runtime (`hyprctl`).

## what's in it

Status bar with workspaces, clock, and live indicators. App launcher (with `=` calculator
and `:` clipboard modes). Notifications. Control center: Wi-Fi/BT/audio device pickers,
sliders, a media card, a resolution + scale switcher, DND, night light. Volume and brightness
OSDs. Power menu. Lock screen (real PAM). Polkit agent. Wallpaper and theme switchers (18
wallust palettes, live restyle). A settings panel where the whole control-center layout is
editable. And a calendar. Night Light and Game Mode are toggleable "modes." It all morphs out
of the one island.

## gotchas (a.k.a. the scars)

The stuff that'll eat yer whole afternoon if you forget it:

1. **Hot-reload lies to your face.** This build reliably reloads *value* changes (Theme
   tokens, Config fields) but real often just refuses to re-render structural edits (new
   widgets, swapped components, changed `Repeater` models) while cheerfully logging
   "Configuration Loaded" with zero errors. If your markup didn't show up, `qs kill` and
   relaunch. Never trust a hot-reload for anything structural. This one wastes the most time
   by far.
2. **Bar's on one monitor / vanished on unplug?** You forgot
   `Variants { model: Quickshell.screens }`.
3. **`ReferenceError: x is not defined`** from a moved Process/Timer means you reached for an
   `id` across a file boundary. Use a singleton.
4. **Pipewire nodes keep going null** until you give 'em a `PwObjectTracker` to stay bound.
   Took way too long to figure that out.
5. **Popups won't dismiss on click-outside** without a `HyprlandFocusGrab` or a full-screen
   input-catching backdrop.
6. **State vanishes on reload** because singletons re-init. Persist anything that matters via
   `Config` or `PersistentProperties`.
7. **Only ONE polkit agent per session.** If the prompt never shows or `isRegistered` is
   false, some other agent grabbed it first (hyprpolkitagent, polkit-gnome, polkit-kde,
   lxqt-policykit, mate-polkit). Kill it.
8. **Battery's a trap.** `percentage` is 0..1 (so times 100), and "charging" has to be
   `state === Charging`. `!onBattery` only means "on AC": a plugged-in laptop sitting at 80%
   reports PendingCharge, not Charging. Same gotcha with `signalStrength` everywhere, 0..1.
9. **`hyprctl keyword` is dead here.** This Hyprland runs the Lua-config parser, which flat
   out rejects `hyprctl keyword` ("use eval"). Anything that poses Hyprland at runtime (Game
   Mode, the resolution/scale switcher) has to go through `hyprctl eval 'hl.config{...}'` or
   `hl.monitor{}`.

## two surfaces to handle with care

The lock screen and polkit are the security-critical ones, so for both: authenticate ONLY
through the real thing (PAM / polkitd), never compare a password yourself, never cache or log
it, grab keyboard focus exclusively, and fail closed. Any error means stay locked or cancel
the request, never dump to the desktop and never fake success.

One genuinely scary detail, written down so nobody "fixes" it: the lock screen's PAM config
is `"su"`, NOT `"login"`. On this host, `"login"` (pam_unix with `try_first_pass nullok` plus
faillock) *accepted a wrong password* through Quickshell's conversation. As in, it failed
**open**. Yeah. `"su"` (plain pam_unix) rejects it like it should. Do not switch it back, and
re-test a wrong password after any PAM change. I mean it.
