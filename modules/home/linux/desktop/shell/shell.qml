//@ pragma UseQApplication
// EVERY text surface renders through fontconfig. Qt Quick's own default is QtTextRendering,
// a distance field, which ignores hinting and does grayscale-only AA, so none of
// ~/.config/fontconfig (hintslight, rgb subpixel, lcddefault) reaches it. This flips the
// application-wide default to native, which is what actually reads those settings. It
// matters because the shell is full of raw Text/TextInput elements that don't go through
// StyledText (the search fields, the lock screen, the settings window), and those follow
// the default, not StyledText's explicit setting. Read once at startup: needs a full
// restart, not a hot reload.
//@ pragma NativeTextRendering
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "config"
import "theme"
import "services"
import "modules/bar"
import "modules/notifications"
import "modules/osd"
import "modules/logout"
import "modules/lock"
import "modules/polkit"
import "modules/wallpaper"
import "modules/settings"
import "modules/screencorners"
import "modules/keys"

ShellRoot {
    // Flip any "mode" and morph the island into its status indicator (ringed icon +
    // label, accent ring when on, struck-through grey when off) through the OSD's
    // transient machinery, which auto-hides on the focused monitor. Want a new mode?
    // Make a service singleton exposing { label, iconName, enabled, toggle() } (copy
    // NightLight or GameMode), then add a GlobalShortcut + IpcHandler below that call
    // toggleMode(<Service>).
    // Game Mode turns the shell's effects off wholesale (durations to 0, shadows off), the
    // same trade it makes on Hyprland's side. Bound here because theme/ can't import services/.
    Binding { target: Theme; property: "gameMode"; value: GameMode.enabled }

    function toggleMode(m) {
        m.toggle();
        OsdState.showMode(m.label, m.iconName, m.enabled, Hyprland.focusedMonitor?.name ?? "");
    }

    // Wallpaper: one background-layer surface per monitor.
    Variants {
        model: Quickshell.screens
        Wallpaper {}
    }

    // Rounded display corners: one click-through overlay per monitor, purely cosmetic.
    Variants {
        model: Quickshell.screens
        ScreenCorners {}
    }

    // Wallpaper picker rides the bar's island now (see modules/wallpaper/WallpaperContent.qml).
    GlobalShortcut {
        name: "wallpaper"
        description: "Toggle the wallpaper picker"
        onPressed: GlobalState.toggleWallpaperPicker()
    }

    // Settings is its OWN floating window now (not an island morph). It stays mapped while
    // GlobalState.settingsOpen; the shortcut / IpcHandler below just toggle that. On Hyprland
    // add a float windowrule for title "Settings" so it doesn't tile.
    SettingsWindow {}
    GlobalShortcut {
        name: "settings"
        description: "Toggle the settings window"
        onPressed: GlobalState.toggleSettings()
    }

    // Calendar morphs the bar's island (pressing the clock opens it too, see
    // modules/bar/Bar.qml + modules/calendar/CalendarContent.qml).
    GlobalShortcut {
        name: "calendar"
        description: "Toggle the calendar"
        onPressed: GlobalState.toggleCalendar()
    }

    // One bar per connected monitor. Variants hands each delegate its own `modelData`
    // (a ShellScreen); unplug or replug a monitor and its bar comes and goes with it.
    Variants {
        model: Quickshell.screens
        Bar {}
    }

    // App launcher lives in the bar's island now: the island itself morphs into
    // the launcher (see modules/bar/Bar.qml + modules/launcher/LauncherContent.qml).
    // The GlobalShortcut / IpcHandler below just toggle GlobalState.launcherOpen.

    // Pre-warm the app list (DesktopEntries enumeration) + the icon theme a beat
    // after startup, so the first launcher open is instant instead of eating that
    // cost on first show. Deferred 'cause we don't want it holding up the bar.
    Timer {
        interval: 600
        running: true
        repeat: false
        onTriggered: {
            const n = Apps.all.length;            // touch it to force enumeration
            Quickshell.iconPath("application-x-executable"); // warm the icon theme
        }
    }

    // Notification popups morph the bar's island now (it shows the incoming
    // notification, then reverts); see modules/bar/Bar.qml + NotificationIsland.qml.
    // History still lives in the control center.

    // Control center lives in the bar's island now: the island morphs into it,
    // opened from the island's cc pill. See modules/controlcenter/ControlCenterContent.qml.
    // The GlobalShortcut / IpcHandler below just toggle GlobalState.controlCenterOpen.

    // On-screen displays (volume/brightness) morph the bar's island now: it becomes
    // a level pill, then reverts (see modules/bar/Bar.qml + OsdIsland.qml).
    // OsdManager watches Audio/Brightness and drives OsdState; the standalone OSD
    // window is retired, same as NotificationStack.
    OsdManager {}

    // The bottom-centre toast ("Copied to clipboard"): OsdState.showHud() from inside the
    // shell, the `hud` IpcHandler below from outside it.
    Hud {}

    // Power menu morphs the bar's island now (see modules/logout/LogoutContent.qml).
    GlobalShortcut {
        name: "logout"
        description: "Toggle the power menu"
        onPressed: GlobalState.toggleLogout()
    }

    // Keyboard help: the cheat sheet that floats while a Hyprland submap is active, and the
    // full shortcut sheet. Both list what `hyprctl binds -j` reports, so binds need a
    // description to appear (see services/Keybinds.qml).
    SubmapOverlay {}
    ShortcutSheet {}
    GlobalShortcut {
        name: "keys"
        description: "Toggle the keyboard shortcut sheet"
        onPressed: Keybinds.toggleSheet()
    }

    // Lock screen. Kicked off by GlobalState.lockRequested() (from the power menu,
    // the shortcut, or IPC), which calls LockState.lock().
    Lock {}

    // Polkit auth agent (session-global). The bar's island morphs into the auth
    // prompt now (modules/polkit/PolkitContent.qml). This Connections instantiates
    // the Polkit singleton so the agent registers at startup, before any request
    // shows up. Without that, escalation prompts just silently fail.
    Connections { target: Polkit }

    Connections {
        target: GlobalState
        function onLockRequested() { LockState.lock(); }
    }

    GlobalShortcut {
        name: "lock"
        description: "Lock the screen"
        onPressed: GlobalState.requestLock()
    }

    // Global shortcut. Bind it over in hyprland.conf:
    //   bind = SUPER, SPACE, global, quickshell:launcher
    GlobalShortcut {
        name: "launcher"
        description: "Toggle the app launcher"
        onPressed: GlobalState.toggleLauncher()
    }

    // Brightness keys, done in-process (no `qs ipc` spawn) so they're instant and
    // repeat smoothly on key-hold. Bind with a repeating bind, e.g. in binds.lua:
    //   bindle = , XF86MonBrightnessUp,   global, quickshell:brightnessUp
    //   bindle = , XF86MonBrightnessDown, global, quickshell:brightnessDown
    GlobalShortcut {
        name: "brightnessUp"
        description: "Brightness +5% (focused monitor)"
        onPressed: { const m = Brightness.focused(); if (m) m.setBrightness(m.percentage + Config.brightnessStep); }
    }
    GlobalShortcut {
        name: "brightnessDown"
        description: "Brightness -5% (focused monitor)"
        onPressed: { const m = Brightness.focused(); if (m) m.setBrightness(m.percentage - Config.brightnessStep); }
    }

    // Volume keys, also in-process. Bind with repeating binds, e.g.:
    //   bindle = , XF86AudioRaiseVolume, global, quickshell:volumeUp
    //   bindle = , XF86AudioLowerVolume, global, quickshell:volumeDown
    //   bind   = , XF86AudioMute,        global, quickshell:volumeMute
    GlobalShortcut {
        name: "volumeUp"
        description: "Volume +5%"
        onPressed: Audio.setVolume(Audio.volume + Config.volumeStep / 100)
    }
    GlobalShortcut {
        name: "volumeDown"
        description: "Volume -5%"
        onPressed: Audio.setVolume(Audio.volume - Config.volumeStep / 100)
    }
    GlobalShortcut {
        name: "volumeMute"
        description: "Toggle mute"
        onPressed: Audio.toggleMute()
    }

    GlobalShortcut {
        name: "nightlight"
        description: "Toggle Night Light"
        onPressed: toggleMode(NightLight)
    }
    GlobalShortcut {
        name: "gamemode"
        description: "Toggle Game Mode (disable Hyprland effects)"
        onPressed: toggleMode(GameMode)
    }

    // Portable / test hook:  qs ipc call launcher toggle|open|close
    IpcHandler {
        target: "launcher"
        function toggle() { GlobalState.toggleLauncher(); }
        function open() { GlobalState.launcherOpen = true; }
        function close() { GlobalState.launcherOpen = false; }
    }

    // Portable / test hook:  qs ipc call controlcenter toggle|open|close
    IpcHandler {
        target: "controlcenter"
        function toggle() { GlobalState.toggleControlCenter(); }
        function open() { GlobalState.controlCenterOpen = true; }
        function close() { GlobalState.controlCenterOpen = false; }
    }

    // qs ipc call logout toggle|open|close
    IpcHandler {
        target: "logout"
        function toggle() { GlobalState.toggleLogout(); }
        function open() { GlobalState.logoutOpen = true; }
        function close() { GlobalState.logoutOpen = false; }
    }

    // qs ipc call lock lock
    IpcHandler {
        target: "lock"
        function lock() { GlobalState.requestLock(); }
    }

    // qs ipc call wallpaper toggle|open|close
    IpcHandler {
        target: "wallpaper"
        function toggle() { GlobalState.toggleWallpaperPicker(); }
        function open() { GlobalState.wallpaperPickerOpen = true; }
        function close() { GlobalState.wallpaperPickerOpen = false; }
    }

    // qs ipc call hud show "<text>"  /  qs ipc call hud showIcon "<text>" <icon>
    // where <icon> is a drawn icon name (clipboard, calculator, check, …), an icon theme
    // name, or an absolute image path
    IpcHandler {
        target: "hud"
        function show(text: string): void { OsdState.showHud(text, ""); }
        function showIcon(text: string, icon: string): void { OsdState.showHud(text, icon); }
        function hide(): void { OsdState.hideHud(); }
    }

    // qs ipc call island toggle|open|close: hold the island expanded, no pointer needed
    IpcHandler {
        target: "island"
        function toggle() { GlobalState.toggleIsland(); }
        function open() { GlobalState.islandHold = true; }
        function close() { GlobalState.islandHold = false; }
    }

    // qs ipc call keys toggle|open|close: the keyboard shortcut sheet
    IpcHandler {
        target: "keys"
        function toggle() { Keybinds.toggleSheet(); }
        function open() { Keybinds.openSheet(); }
        function close() { Keybinds.closeSheet(); }
    }

    // qs ipc call settings toggle|open|close
    IpcHandler {
        target: "settings"
        function toggle() { GlobalState.toggleSettings(); }
        function open() { GlobalState.settingsOpen = true; }
        function close() { GlobalState.settingsOpen = false; }
    }

    // qs ipc call calendar toggle|open|close
    IpcHandler {
        target: "calendar"
        function toggle() { GlobalState.toggleCalendar(); }
        function open() { GlobalState.calendarOpen = true; }
        function close() { GlobalState.calendarOpen = false; }
    }

    // qs ipc call nightlight toggle  /  qs ipc call gamemode toggle
    IpcHandler {
        target: "nightlight"
        function toggle() { toggleMode(NightLight); }
    }
    IpcHandler {
        target: "gamemode"
        function toggle() { toggleMode(GameMode); }
    }

    // Brightness control: bind your keys to these so changes route through the
    // shell (runs brightnessctl/ddcutil setvcp, updates the control center, and
    // fires the OSD). e.g. in binds.lua: `qs ipc call brightness adjustFocused 5`.
    IpcHandler {
        target: "brightness"

        // Adjust/set a specific display by connector name (e.g. "DP-1", "eDP-1").
        function adjust(name: string, delta: int): void {
            const m = Brightness.forName(name);
            if (m) m.setBrightness(m.percentage + delta);
        }
        function set(name: string, value: int): void {
            const m = Brightness.forName(name);
            if (m) m.setBrightness(value);
        }

        // Adjust/set whichever monitor is focused (bind brightness up/down here).
        function adjustFocused(delta: int): void {
            const m = Brightness.focused();
            if (m) m.setBrightness(m.percentage + delta);
        }
        function setFocused(value: int): void {
            const m = Brightness.focused();
            if (m) m.setBrightness(value);
        }
    }
}
