pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Per-monitor SCALE switcher (that's its main job); resolution apply is kept around too.
// Quickshell has no native binding for monitor config, so we do it shell-native: read the
// state out of `hyprctl -j monitors`, then apply a change by driving Hyprland straight via
// `hyprctl eval 'hl.monitor{}'`. That's the Lua-config stand-in for `hyprctl keyword
// monitor`, which this config's Lua parser flat-out rejects (same gotcha as GameMode). One
// of the only three spots we're allowed to shell out to a Process.
//
// Every change repacks all the monitors left-to-right, gapless, in a collision-safe order
// so none of 'em overlap even for a frame (Hyprland warns and refuses if they do). All the
// hl.monitor statements go in ONE eval so they run in sequence, in that order. Runtime
// only: a `hyprctl reload` throws it all back to monitors.lua.
Singleton {
    id: root

    // [{ name, width, height, refresh, hz, scale, x, y, transform, focused,
    //    modes: [{ label, sublabel, mode, w, h, rr }] }]
    property var monitors: []
    property bool busy: false

    // Candidate scales. Only the ones that divide a monitor's mode into whole logical
    // pixels are offered (scalesFor): Hyprland silently snaps any other scale to a nearby
    // one, so on a 4K TV 1.75 would come back as something else and the chip that was
    // pressed would never show as current.
    readonly property var scaleOptions: [1.0, 1.25, 1.5, 1.6, 1.75, 2.0, 2.5, 3.0]

    function validScale(w, h, s) {
        const lw = w / s, lh = h / s;
        return Math.abs(lw - Math.round(lw)) < 0.01 && Math.abs(lh - Math.round(lh)) < 0.01
            && Math.round(lh) >= 600;   // below this the shell's own panels stop fitting
    }
    // the scales worth offering for this monitor's current mode, its current scale always
    // among them
    function scalesFor(m) {
        if (!m) return [];
        const out = scaleOptions.filter(s => validScale(m.width, m.height, s));
        if (!out.some(s => Math.abs(s - m.scale) < 0.01)) out.push(m.scale);
        return out.sort((a, b) => a - b);
    }
    // the valid scale nearest `s` for a w×h mode, so a mode change never asks Hyprland for
    // a fractional logical size (2.0 on 1920×1080 stays 2.0; 1.25 on 1366×768 does not)
    function _nearestValid(w, h, s) {
        if (validScale(w, h, s)) return s;
        const ok = scaleOptions.filter(c => validScale(w, h, c));
        if (ok.length === 0) return 1.0;
        return ok.reduce((best, c) => Math.abs(c - s) < Math.abs(best - s) ? c : best, ok[0]);
    }

    // the focused monitor (what the cc tile sums up), or the first one if nothing's focused
    readonly property var current: {
        for (let i = 0; i < monitors.length; i++)
            if (monitors[i].focused) return monitors[i];
        return monitors.length ? monitors[0] : null;
    }

    function refresh() { mons.running = true; }

    function fmtScale(s) {
        const r = Math.round(s * 100) / 100;
        return (r % 1 === 0) ? r.toFixed(1) : String(r);
    }

    function _find(name) {
        for (let i = 0; i < monitors.length; i++)
            if (monitors[i].name === name) return monitors[i];
        return null;
    }

    // Set a monitor's scale, keeping its current mode. This is the main way in.
    function setScale(name, scale) {
        const m = _find(name);
        if (!m) return;
        _apply(name, `${m.width}x${m.height}@${m.hz}`, scale);
    }

    // Set a monitor's mode (keeps its current scale unless you pass `scale`). Kept around.
    function setMode(name, mode, scale) {
        const m = _find(name);
        if (!m) return;
        const mm = mode.match(/^(\d+)x(\d+)@/);
        const s = scale !== undefined ? scale : m.scale;
        _apply(name, mode, mm ? _nearestValid(parseInt(mm[1]), parseInt(mm[2]), s) : s);
    }

    // logical width the way Hyprland rounds it (px / scale). Dims swap on 90°/270°
    // rotation (transforms 1,3,5,7).
    function _logicalWidth(w, h, scale, transform) {
        const dim = (transform === 1 || transform === 3 || transform === 5 || transform === 7) ? h : w;
        return Math.floor(dim / scale + 0.5);
    }

    // Apply `mode`+`scale` to monitor `name`, repacking every monitor left-to-right
    // (gapless) in a collision-safe order, all batched into one eval.
    function _apply(name, mode, scale) {
        if (busy) return;
        const snap = monitors.slice().sort((a, b) => a.x - b.x);

        let targetIdx = -1;
        const rows = snap.map((m, i) => {
            if (m.name === name) {
                targetIdx = i;
                const mm = mode.match(/^(\d+)x(\d+)@/);
                const nw = mm ? parseInt(mm[1]) : m.width;
                const nh = mm ? parseInt(mm[2]) : m.height;
                return { name: m.name, mode: mode, scale: scale, y: m.y,
                         lw: _logicalWidth(nw, nh, scale, m.transform) };
            }
            // everyone else keeps their current mode + scale (exact refresh so the pick sticks)
            return { name: m.name, mode: `${m.width}x${m.height}@${m.hz}`, scale: m.scale, y: m.y,
                     lw: _logicalWidth(m.width, m.height, m.scale, m.transform) };
        });
        if (targetIdx < 0) return;

        const oldLw = _logicalWidth(snap[targetIdx].width, snap[targetIdx].height,
                                    snap[targetIdx].scale, snap[targetIdx].transform);

        // pack 'em left-to-right from x=0
        let cx = 0;
        for (let i = 0; i < rows.length; i++) { rows[i].x = cx; cx += rows[i].lw; }

        // order matters here or we get a transient overlap. Growing (and a smaller scale
        // means wider, too): shove the right-side monitors out first, rightmost first, then
        // the target. Shrinking: target first, then pull the right side back in. Anything
        // left of the target only shifts its x.
        let order = [];
        if (rows[targetIdx].lw >= oldLw) {
            for (let i = rows.length - 1; i > targetIdx; i--) order.push(rows[i]);
            order.push(rows[targetIdx]);
        } else {
            order.push(rows[targetIdx]);
            for (let i = targetIdx + 1; i < rows.length; i++) order.push(rows[i]);
        }
        for (let i = targetIdx - 1; i >= 0; i--) order.push(rows[i]);

        // fixed digits, so float noise like 1.2499999999 never reaches Hyprland's snapping
        const lua = order.map(r =>
            `hl.monitor({ output = "${r.name}", mode = "${r.mode}", position = "${r.x}x${r.y}", scale = ${Number(r.scale).toFixed(4)} })`
        ).join(" ");

        busy = true;
        Quickshell.execDetached(["hyprctl", "eval", lua]);
        reapply.restart();
    }

    // Hyprland applies this async, so re-read once it's settled and the UI catches up.
    Timer { id: reapply; interval: 700; onTriggered: { root.busy = false; root.refresh(); } }

    Process {
        id: mons
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = [];
                try {
                    const arr = JSON.parse(text);
                    for (const m of arr) {
                        const seen = ({});
                        const modes = [];
                        for (const raw of (m.availableModes || [])) {
                            // "2560x1440@143.97200Hz"
                            const mm = raw.match(/^(\d+)x(\d+)@([\d.]+)Hz$/);
                            if (!mm) continue;
                            const w = parseInt(mm[1]);
                            const h = parseInt(mm[2]);
                            const rr = Math.round(parseFloat(mm[3]));
                            const key = `${w}x${h}@${rr}`;
                            if (seen[key]) continue;       // dedupe the near-identical refresh rates
                            seen[key] = true;
                            modes.push({
                                label: `${w} × ${h}`,
                                sublabel: `${rr} Hz`,
                                mode: `${w}x${h}@${mm[3]}`,  // full precision, hl.monitor wants it
                                w: w, h: h, rr: rr
                            });
                        }
                        out.push({
                            name: m.name,
                            width: m.width, height: m.height,
                            refresh: Math.round(m.refreshRate),
                            hz: m.refreshRate,
                            scale: m.scale,
                            x: m.x, y: m.y,
                            transform: m.transform || 0,
                            focused: m.focused === true,
                            modes: modes
                        });
                    }
                } catch (e) {
                    out = [];
                }
                root.monitors = out;
            }
        }
    }
}
