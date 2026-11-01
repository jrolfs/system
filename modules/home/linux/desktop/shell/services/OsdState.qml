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

    // The HUD: a capsule toast at the bottom centre of the focused monitor, Raycast's
    // "Copied to clipboard". Separate from the OSD above because it confirms something
    // that already happened rather than showing a level, and it must not take the island
    // from whatever panel is open. `hudIcon` is a name from components/Icon.qml or, failing
    // that, an icon theme name or an absolute image path. `hudSerial` ticks on every show
    // so a repeat of the same text still replays the entrance.
    property string hudText: ""
    property string hudIcon: ""
    property bool hudActive: false
    property int hudSerial: 0

    function showHud(text, icon) {
        hudText = text || "";
        hudIcon = icon || "";
        hudSerial++;
        hudActive = true;
        hudTimer.restart();
    }
    function hideHud() { hudActive = false; hudTimer.stop(); }

    Timer {
        id: hudTimer
        interval: Config.hudTimeout
        onTriggered: root.hudActive = false
    }
}
