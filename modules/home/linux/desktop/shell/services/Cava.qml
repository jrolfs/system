pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Real-time audio levels for the island's media card. Runs `cava` in raw-ascii mode (it
// does the FFT on the default sink's monitor) and exposes `levels`, `bars` values in
// 0..1, updated per frame. Runs ONLY while a consumer wants it (`demand` > 0, raised by
// the card while it is on screen) and there is a player at all, so an idle shell owns no
// FFT. Not gated on playing: that killed and respawned cava on every pause, and each
// respawn redid its gain calibration from zero; cava idles itself on silence instead
// (sleep_timer in cava.conf).
Singleton {
    id: root

    // the band count comes from cava.conf (`bars`); this follows the first frame
    property int bars: 12
    property var levels: Array(bars).fill(0)
    property int demand: 0
    readonly property bool active: demand > 0 && Media.player !== null

    Process {
        id: proc
        running: root.active
        // our own config next to this file, so the user's ~/.config/cava stays theirs
        command: ["cava", "-p", Quickshell.shellDir + "/services/cava.conf"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const parts = data.split(";");
                if (parts.length > 1 && parts[parts.length - 1] === "") parts.pop();   // the trailing delimiter
                if (parts.length > 1 && parts.length !== root.bars) root.bars = parts.length;
                const out = [];
                for (let i = 0; i < root.bars; i++) {
                    const v = parseInt(parts[i]);
                    out.push(isNaN(v) ? 0 : Math.max(0, Math.min(1, v / 100)));
                }
                root.levels = out;
            }
        }
        onRunningChanged: if (!running) root.levels = Array(root.bars).fill(0)
    }
}
