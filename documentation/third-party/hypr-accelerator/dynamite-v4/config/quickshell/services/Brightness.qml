pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../config"

// Per-display backlight. Internal panels (eDP/LVDS) go through brightnessctl; external
// monitors go through ddcutil over DDC/CI, mapped from DRM connector name -> i2c bus by
// `ddcutil detect`. One controller per screen: consumers call Brightness.forScreen(screen)
// and read .percentage or call .setBrightness().
//
// ddcutil is slow relative to sysfs (a setvcp is ~77ms on the Dell here; it was assumed to
// be ~1s for a long time, which was wrong), so internal gets polled while external is read
// once at startup and written coalesced. Skip the coalescing and one slider drag queues up
// dozens of setvcp calls, and yer brightness lags a mile behind yer finger. Both paths
// FADE: see the ramp below.
Singleton {
    id: root

    // DRM connector (e.g. "DP-1") -> i2c bus number, for DDC-capable externals.
    property var ddcBuses: ({})

    // Fires whenever a display's brightness changes, whether we set it or the internal
    // poll caught a hardware-key press. Drives the brightness OSD.
    signal changed(string name, int value)

    function forName(n) {
        for (let i = 0; i < controllers.count; i++) {
            const o = controllers.objectAt(i);
            if (o && o.name === n)
                return o;
        }
        return null;
    }
    function forScreen(s) { return s ? forName(s.name) : null; }

    // Controller for whichever Hyprland monitor's focused (for the keybinds).
    function focused() {
        const fm = Hyprland.focusedMonitor;
        return fm ? forName(fm.name) : null;
    }

    function refreshAll() {
        for (let i = 0; i < controllers.count; i++) {
            const o = controllers.objectAt(i);
            if (o)
                o.refresh();
        }
    }

    // Sniff out which DRM connectors have a DDC-controllable bus. Runs at startup AND on
    // every monitor hotplug, 'cause i2c bus numbers shift on replug and a freshly connected
    // external isn't in the map until we look again. Debounced, since a replug fires
    // screensChanged a few times in a row and ddcutil detect is dog slow.
    function detectDdc() { if (!ddcDetect.running) ddcDetect.running = true; }
    Component.onCompleted: detectDdc()
    Connections {
        target: Quickshell
        function onScreensChanged() { redetect.restart(); }
    }
    Timer {
        id: redetect
        interval: 1000   // give the new monitor's i2c bus a beat to come up before we look
        onTriggered: { if (ddcDetect.running) restart(); else ddcDetect.running = true; }
    }

    Process {
        id: ddcDetect
        command: ["ddcutil", "detect", "--terse"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                // Each block starts on a non-indented line. Only the "Display N" blocks
                // can be driven over DDC ("Invalid display" means a laptop panel / no DDC).
                for (const blk of text.split(/\n(?=\S)/)) {
                    if (!blk.startsWith("Display "))
                        continue;
                    const bus = blk.match(/i2c-(\d+)/);
                    const conn = blk.match(/card\d+-(\S+)/);
                    if (bus && conn)
                        map[conn[1]] = parseInt(bus[1]);
                }
                root.ddcBuses = map;
                root.refreshAll();
            }
        }
    }

    Instantiator {
        id: controllers
        model: Quickshell.screens

        delegate: Item {
            id: mon
            required property var modelData

            readonly property string name: modelData ? modelData.name : ""
            // Classify by CONNECTOR, not by whether we found a DDC bus. eDP/LVDS/DSI are the
            // built-in panel (brightnessctl); everything else (DP/HDMI) is external (ddcutil).
            // This is the bug fix: if you key off "do we have a bus", a freshly hotplugged
            // DP-1 (bus not detected yet) looks internal and brightnessctl dims the laptop
            // panel instead. An external monitor must NEVER touch brightnessctl.
            readonly property bool internal: /^(eDP|LVDS|DSI)/i.test(name)
            readonly property int ddcBus: root.ddcBuses[name] ?? -1
            readonly property bool external: !internal
            readonly property bool ready: percentage >= 0
            property int percentage: -1

            onPercentageChanged: if (percentage >= 0) root.changed(name, percentage)

            function refresh() {
                if (internal)
                    intGet.running = true;
                else if (ddcBus >= 0)   // external, but only once we know its bus
                    ddcGet.running = true;
            }

            // External write path, coalesced so a held key tracks as fast as ddcutil can
            // manage: write now if we're idle, else stash the latest value and fire it the
            // moment the in-flight setvcp returns. We never build up a queue.
            property int extPending: -1
            function flushExt() {
                if (extPending < 0 || ddcSet.running)
                    return;
                const v = extPending;
                extPending = -1;
                hw = v;
                ddcSet.command = ["ddcutil", "--bus", String(mon.ddcBus), "setvcp", "10", String(v)];
                ddcSet.running = true;
            }

            function setBrightness(pct) {
                const p = Math.max(0, Math.min(100, Math.round(pct)));
                if (internal) {
                    percentage = p; // optimistic, so the OSD + control center move instantly
                    startRamp(p);   // the hardware FADES there (below)
                } else if (ddcBus >= 0) {
                    percentage = p;
                    startRamp(p);   // externals fade too, throttled to what DDC can take
                }
                // external whose bus we haven't sniffed out yet: do NOTHING. Falling back to
                // brightnessctl here is exactly what dimmed the wrong monitor. The re-detect
                // on hotplug (below) gives us the bus in a beat and then it works.
            }

            // --- an eased hardware RAMP, for both write paths ---
            // A brightness change fades instead of stepping (the way macOS does it): the
            // value written to the hardware eases from wherever it is to the target,
            // ease-out, so it moves fast at first and lands softly. Retargetable mid-flight:
            // a held key or a slider drag becomes one continuous glide rather than a
            // staircase. The ramp only ever PUSHES into the coalesced write queue (one
            // brightnessctl / setvcp in flight, newest value always lands), so it throttles
            // itself to whatever the hardware can take and can never queue up behind itself.
            // Externals get a longer ramp: a DDC write is ~77ms on the Dell here (measured;
            // the old "about a second" was wrong), so ~380ms buys five real steps and the
            // panel's own backlight response smooths the rest.
            readonly property int rampMs: Config.reducedMotion ? 0 : (internal ? 260 : 380)
            property real rampFrom: -1
            property int rampTo: -1
            property double rampStart: 0
            property double rampEndedAt: 0
            property int hw: -1            // what we believe the backlight is at right now
            property int intPending: -1

            function rampValue() {
                if (rampTo < 0) return hw;
                if (rampMs <= 0) return rampTo;
                const t = Math.max(0, Math.min(1, (Date.now() - rampStart) / rampMs));
                const e = 1 - Math.pow(1 - t, 3);
                return Math.round(rampFrom + (rampTo - rampFrom) * e);
            }
            function flushInt() {
                if (intPending < 0 || intSet.running) return;
                const v = intPending;
                intPending = -1;
                hw = v;
                intSet.command = ["brightnessctl", "set", `${v}%`];
                intSet.running = true;
            }
            // hand a value to this display's write queue (whichever kind it is)
            function push(v) {
                if (internal) { intPending = v; flushInt(); }
                else if (ddcBus >= 0) { extPending = v; flushExt(); }
            }
            readonly property int pending: internal ? intPending : extPending
            function startRamp(p) {
                rampFrom = rampTick.running ? rampValue() : (hw >= 0 ? hw : p);
                rampTo = p;
                rampStart = Date.now();
                if (rampMs <= 0 || rampFrom === rampTo) {
                    rampTick.stop();
                    rampTo = -1;
                    rampEndedAt = Date.now();
                    push(p);
                    return;
                }
                rampTick.start();
            }
            Timer {
                id: rampTick
                interval: 16
                repeat: true
                onTriggered: {
                    const v = mon.rampValue();
                    if (v !== mon.hw && v !== mon.pending) mon.push(v);
                    if (Date.now() - mon.rampStart >= mon.rampMs) {
                        rampTick.stop();
                        if (mon.hw !== mon.rampTo) mon.push(mon.rampTo);   // the exact target lands last
                        mon.rampTo = -1;
                        mon.rampEndedAt = Date.now();
                    }
                }
            }

            Process {
                id: intGet
                command: ["brightnessctl", "-m"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const f = text.trim().split(",");
                        if (f.length < 4) return;
                        const v = parseInt(f[3]); // "30%" -> 30
                        // Mid-ramp (and for a beat after) the hardware is deliberately behind
                        // the target; letting the poll write that back would drag the UI down
                        // the ramp we're climbing. Hardware-key presses still land as before
                        // once nothing is in flight.
                        if (rampTick.running || Date.now() - mon.rampEndedAt < 500) return;
                        mon.hw = v;
                        mon.percentage = v;
                    }
                }
            }
            Process {
                id: intSet
                onRunningChanged: if (!running) mon.flushInt()   // the newest value always lands
            }

            // --- external (ddcutil) ---
            Process {
                id: ddcGet
                command: ["ddcutil", "--bus", String(mon.ddcBus), "--brief", "getvcp", "10"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const p = text.trim().split(/\s+/); // "VCP 10 C <cur> <max>"
                        if (p.length >= 5 && p[2] === "C") {
                            const cur = parseInt(p[3]);
                            const max = parseInt(p[4]);
                            if (max > 0) {
                                mon.percentage = Math.round(cur / max * 100);
                                mon.hw = mon.percentage;
                            }
                        }
                    }
                }
            }
            Process {
                id: ddcSet
                onRunningChanged: if (!running) mon.flushExt() // flush out any newer pending value
            }

            // Poll the internal panel only (it's fast); externals get read once via refreshAll().
            Timer {
                interval: Config.brightnessPoll
                running: !mon.external
                repeat: true
                onTriggered: mon.refresh()
            }
        }
    }
}
