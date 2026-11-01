pragma Singleton
import Quickshell
import "../config"

// Game Mode: rips out Hyprland's fancy effects (animations, blur, window shadows) for the
// frames, and puts 'em all back when you switch it off. Toggled like any other "mode": see
// the standard interface below (label + iconName + enabled + toggle()), which is what
// shell.qml's toggleMode() hangs the island indicator off of.
//
// This config gets loaded by Hyprland's Lua parser, and under that parser `hyprctl keyword`
// is rejected outright ("non-legacy parser, use eval"). So we run Lua through `hyprctl
// eval`, calling the config's own `hl.config{}` setter (same one the modules use at load).
// No native binding for Hyprland config, so this is one of the few spots we shell out.
Singleton {
    id: root

    // standard "mode" interface
    readonly property string label: "Game Mode"
    readonly property string iconName: "controller"

    property bool enabled: false   // session-local
    // What leaving Game Mode puts back. Nix writes these into Config from the same values
    // hyprland.nix declares, so they cannot drift from Hyprland's own config.
    readonly property int gapsIn: Config.hyprGapsIn
    readonly property int gapsOut: Config.hyprGapsOut
    readonly property int rounding: Config.hyprRounding

    function toggle() { enabled = !enabled; apply(); }

    function apply() {
        // game mode ON means effects OFF, gaps 0, square windows (and the reverse on the
        // way back). The effect params (blur size, shadow range, anim curves) stay loaded,
        // so just flipping :enabled brings the whole look back. Gaps + rounding don't work
        // that way though, they need real numbers, so we hand back the configured ones.
        const e = enabled ? "false" : "true";
        const gi = enabled ? 0 : gapsIn;
        const go = enabled ? 0 : gapsOut;
        const r = enabled ? 0 : rounding;
        Quickshell.execDetached(["hyprctl", "eval",
            "hl.config({ animations = { enabled = " + e + " }, " +
            "decoration = { rounding = " + r + ", blur = { enabled = " + e + " }, shadow = { enabled = " + e + " } }, " +
            "general = { gaps_in = " + gi + ", gaps_out = " + go + " } })"]);
    }
}
