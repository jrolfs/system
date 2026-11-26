pragma Singleton
import QtQuick
import Quickshell
import "../config"

// Night light (blue-light filter) via hyprsunset. On: fire up hyprsunset at a warm
// temperature (a detached daemon that hangs onto the gamma). Off: kill it, which
// lets go of the gamma and puts colour back to normal. No native binding, so it's
// one of the few legit Process uses (same deal as brightness). State is session-local.
Singleton {
    id: root

    // standard "mode" interface (see GameMode.qml): label + iconName + enabled +
    // toggle(). shell.qml's toggleMode() drives the island indicator off these.
    readonly property string label: "Night Light"
    readonly property string iconName: "night"

    property bool enabled: false
    property int temperature: Config.nightLightTemp   // warm, in K

    function toggle() { enabled = !enabled; apply(); }

    function apply() {
        if (enabled)
            // (re)start the daemon at the current temperature. pkill first is only needed on
            // ENABLE, to guarantee one clean daemon; live temperature changes use setTemp().
            Quickshell.execDetached(["sh", "-c", "pkill hyprsunset 2>/dev/null; hyprsunset -t " + temperature]);
        else
            Quickshell.execDetached(["pkill", "hyprsunset"]);
    }

    // Live temperature change while Night Light is on, through the daemon's own socket:
    // `hyprctl hyprsunset temperature K` (hyprsunset 0.4). A second `hyprsunset -t K` does
    // NOT forward to the running daemon, it dies with "A CTM manager is already running on
    // the current compositor" and the tint never moves (that was the broken slider), and a
    // pkill + respawn flashes the gamma. Throttled to ~90ms so a drag updates the tint in
    // smooth steps instead of spawning a process per pixel.
    property int _pendingTemp: -1
    function setTemp(k) {
        temperature = k;                       // drives the UI live (fill, subtitle)
        if (!enabled) return;
        _pendingTemp = k;
        if (!tempThrottle.running) { flushTemp(); tempThrottle.start(); }
    }
    function flushTemp() {
        if (_pendingTemp < 0) return;
        Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", String(_pendingTemp)]);
        _pendingTemp = -1;
    }
    Timer { id: tempThrottle; interval: 90; onTriggered: root.flushTemp() }
}
