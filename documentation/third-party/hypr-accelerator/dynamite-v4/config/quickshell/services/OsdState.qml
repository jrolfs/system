pragma Singleton
import QtQuick
import Quickshell
import "../config"

// Shared state for the on-screen display. Only one OSD at a time: every show() kicks
// the hide timer back to zero (so spamming volume/brightness refreshes the same OSD
// instead of stacking up a pile of 'em), then it auto-hides after a short delay.
Singleton {
    id: root

    property string kind: ""      // "volume" | "brightness" | "mode"
    property int value: 0          // 0..100
    property bool muted: false     // volume only
    // generic toggle-mode indicator (Night Light, Game Mode, whatever)
    property string modeLabel: ""
    property string modeIcon: ""
    property bool modeOn: false
    property string screen: ""     // connector to show it on (the focused monitor)
    property bool active: false

    function showVolume(v, m, scr) {
        kind = "volume"; value = v; muted = m; screen = scr || "";
        bump();
    }
    function showBrightness(v, scr) {
        kind = "brightness"; value = v; screen = scr || "";
        bump();
    }
    function showMode(label, icon, on, scr) {
        kind = "mode"; modeLabel = label; modeIcon = icon; modeOn = on; screen = scr || "";
        bump();
    }
    function bump() {
        active = true;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: Config.osdTimeout
        onTriggered: root.active = false
    }
}
