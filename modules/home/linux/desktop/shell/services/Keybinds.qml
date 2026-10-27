pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Hyprland's keybindings as rows for the two help surfaces: the submap cheat sheet and the
// shortcut sheet. The binds come from `hyprctl binds -j`, so the sheets list what Hyprland
// actually has loaded rather than a second copy that could drift from hyprland.nix. Only
// binds with a description show up, and a description reads "Group · Label".
Singleton {
    id: root

    // Every described bind, merged and collapsed:
    // [{ submap, group, section, label, alts: [["⌘", "Space"], ...], search }]
    property var rows: []
    // The active submap, "" for Hyprland's default one.
    property string submap: ""
    property bool sheetOpen: false

    // Sheet groups in this order; any other group follows them in the order it first appears.
    readonly property var groupOrder: ["Shell", "Windows", "Window mode", "Workspaces", "Screenshots", "Media"]

    readonly property var groups: {
        const byTitle = {};
        const titles = [];
        for (const row of rows) {
            if (!byTitle[row.group]) { byTitle[row.group] = []; titles.push(row.group); }
            byTitle[row.group].push(row);
        }
        const rank = title => {
            const i = groupOrder.indexOf(title);
            return i >= 0 ? i : groupOrder.length + titles.indexOf(title);
        };
        return titles.slice().sort((a, b) => rank(a) - rank(b)).map(title => ({ title, rows: byTitle[title] }));
    }

    function refresh() { if (!bindsProc.running) bindsProc.running = true; }
    function openSheet() { refresh(); sheetOpen = true; }
    function closeSheet() { sheetOpen = false; }
    function toggleSheet() { if (sheetOpen) closeSheet(); else openSheet(); }

    function title(submapName) {
        return submapName.length > 0 ? submapName[0].toUpperCase() + submapName.slice(1) : "";
    }

    // A submap's binds split into sections by their "Section · " prefix, in config order.
    function sections(submapName) {
        const out = [];
        for (const row of rows) {
            if (row.submap !== submapName) continue;
            const last = out[out.length - 1];
            if (last && last.title === row.section) last.rows.push(row);
            else out.push({ title: row.section, rows: [row] });
        }
        return out;
    }

    // Hyprland's modmask bits
    readonly property int maskShift: 1
    readonly property int maskCtrl: 4
    readonly property int maskAlt: 8
    readonly property int maskSuper: 64
    readonly property int maskHyper: maskShift | maskCtrl | maskAlt | maskSuper

    readonly property var keyNames: ({
        "space": "Space", "return": "↵", "enter": "↵", "kp_enter": "↵", "escape": "Esc", "tab": "⇥",
        "left": "←", "right": "→", "up": "↑", "down": "↓",
        "comma": ",", "period": ".", "slash": "/", "backslash": "\\", "semicolon": ";",
        "apostrophe": "'", "grave": "`", "minus": "-", "equal": "=",
        "bracketleft": "[", "bracketright": "]",
        "delete": "⌦", "backspace": "⌫", "home": "Home", "end": "End",
        "prior": "PgUp", "next": "PgDn", "page_up": "PgUp", "page_down": "PgDn", "print": "Print",
        "mouse:272": "Drag", "mouse:273": "Right-drag", "mouse:274": "Middle-drag",
        "mouse_up": "Scroll ↑", "mouse_down": "Scroll ↓",
        "xf86audioraisevolume": "Vol +", "xf86audiolowervolume": "Vol −", "xf86audiomute": "Mute",
        "xf86audiomicmute": "Mic mute", "xf86audioplay": "Play", "xf86audiopause": "Pause",
        "xf86audionext": "Next", "xf86audioprev": "Previous", "xf86audiostop": "Stop",
        "xf86monbrightnessup": "Bright +", "xf86monbrightnessdown": "Bright −"
    })

    // ⇧/ is what a Mac calls ⌘?, so the shift folds into the glyph instead of its own cap.
    function shiftFolds(key, mask) { return (mask & maskShift) !== 0 && key.toLowerCase() === "slash"; }

    function modifierCaps(mask, key) {
        if ((mask & maskHyper) === maskHyper) return ["Hyper"];
        const caps = [];
        if (mask & maskCtrl) caps.push("⌃");
        if (mask & maskAlt) caps.push("⌥");
        if ((mask & maskShift) && !shiftFolds(key, mask)) caps.push("⇧");
        if (mask & maskSuper) caps.push("⌘");
        return caps;
    }

    function keyCap(key, mask) {
        if (shiftFolds(key, mask)) return "?";
        const named = keyNames[key.toLowerCase()];
        if (named !== undefined) return named;
        if (key.length === 1) return key.toUpperCase();
        return key.replace(/^XF86/, "");
    }

    function digitRange(digits) {
        const sorted = digits.map(Number).sort((a, b) => a - b);
        const contiguous = sorted.every((d, i) => i === 0 || d === sorted[i - 1] + 1);
        if (sorted.length === 1) return String(sorted[0]);
        return contiguous ? `${sorted[0]}–${sorted[sorted.length - 1]}` : sorted.join(",");
    }

    readonly property var arrowCaps: ["←", "→", "↑", "↓"]

    // Splits "Group · Label" into where the row goes. In a submap the group is the submap
    // itself, so a leading "Window mode · " is dropped and a further "Section · " splits the
    // cheat sheet into gapped sections.
    function placement(description, submapName) {
        const parts = description.split(" · ").map(p => p.trim());
        if (submapName === "") {
            if (parts.length === 1) return { group: "Other", section: "", label: parts[0] };
            return { group: parts[0], section: "", label: parts.slice(1).join(" · ") };
        }
        const group = `${title(submapName)} mode`;
        const rest = parts.length > 1 && parts[0] === group ? parts.slice(1) : parts;
        if (rest.length === 1) return { group, section: "", label: rest[0] };
        return { group, section: rest[0], label: rest.slice(1).join(" · ") };
    }

    // A run of binds that differ only in a number or a direction, as rows: "Go to workspace
    // 1–9" for ⌃1 to ⌃9, "Focus" for ⌘ and all four arrows. An incomplete set of arrows
    // stays one row per direction.
    function expandRun(run) {
        const base = { submap: run.submap, group: run.group, section: run.section };
        if (run.kind === "digits") {
            const range = digitRange(run.values);
            return [Object.assign({ label: `${run.base} ${range}`, alts: [run.mods.concat([range])] }, base)];
        }
        if (["left", "right", "up", "down"].every(d => run.values.indexOf(d) >= 0))
            return [Object.assign({ label: run.base, alts: [run.mods.concat(["Arrows"])] }, base)];
        return run.values.map(direction => Object.assign({
            label: `${run.base} ${direction}`, alts: [run.mods.concat([keyNames[direction]])]
        }, base));
    }

    // Alternatives that are the same modifiers on all four arrows read as one "⌥ Arrows".
    function collapseArrows(alts) {
        const slots = [];
        const byModifiers = {};
        for (const alt of alts) {
            const last = alt[alt.length - 1];
            if (arrowCaps.indexOf(last) < 0) { slots.push({ alts: [alt] }); continue; }
            const modifiers = alt.slice(0, -1);
            const slotKey = modifiers.join(" ");
            if (!byModifiers[slotKey]) { byModifiers[slotKey] = { modifiers, keys: [] }; slots.push(byModifiers[slotKey]); }
            byModifiers[slotKey].keys.push(last);
        }
        // QML's JavaScript engine has no Array.prototype.flatMap
        return slots.reduce((out, slot) => {
            if (slot.alts) return out.concat(slot.alts);
            if (arrowCaps.every(cap => slot.keys.indexOf(cap) >= 0)) return out.concat([slot.modifiers.concat(["Arrows"])]);
            return out.concat(slot.keys.map(cap => slot.modifiers.concat([cap])));
        }, []);
    }

    function ingest(text) {
        let list;
        try { list = JSON.parse(text); } catch (e) { console.warn("Keybinds: unreadable `hyprctl binds -j` output"); return; }
        if (!Array.isArray(list)) return;

        const ordered = [];
        // Runs are keyed by their modifiers too, so ⌃1..9 and Hyper+1..9 interleaved in the
        // config still form two runs.
        const runs = {};
        for (const bind of list) {
            const description = String(bind.description ?? "").trim();
            if (description === "") continue;
            const submapName = bind.submap ?? "";
            const { group, section, label } = placement(description, submapName);
            const key = String(bind.key ?? "");
            const lowerKey = key.toLowerCase();
            const mask = Number(bind.modmask ?? 0);
            const mods = modifierCaps(mask, key);

            const numbered = /^[1-9]$/.test(key) ? label.match(/^(.*?)\s*([1-9])$/) : null;
            const directed = ["left", "right", "up", "down"].indexOf(lowerKey) >= 0
                ? label.match(/^(.*?)\s+(left|right|up|down)$/i) : null;
            const run = numbered && numbered[2] === key ? { kind: "digits", base: numbered[1], value: key }
                : directed && directed[2].toLowerCase() === lowerKey ? { kind: "arrows", base: directed[1], value: lowerKey }
                : null;
            if (run) {
                const runKey = [submapName, group, section, mask, run.kind, run.base].join("\u0001");
                if (runs[runKey]) { runs[runKey].values.push(run.value); continue; }
                runs[runKey] = { submap: submapName, group, section, kind: run.kind, base: run.base, values: [run.value], mods };
                ordered.push(runs[runKey]);
                continue;
            }
            ordered.push({ submap: submapName, group, section, label,
                           alts: [mods.concat([bind.catch_all ? "Any key" : keyCap(key, mask)])] });
        }

        // Two binds with the same description (⌥⇧3 and ⌘⇧3 both taking a screenshot) are
        // one row with alternative keys.
        const merged = [];
        const byLabel = {};
        for (const entry of ordered) {
            for (const row of entry.kind === undefined ? [entry] : expandRun(entry)) {
                const labelKey = [row.submap, row.group, row.section, row.label].join("\u0001");
                const existing = byLabel[labelKey];
                if (!existing) { byLabel[labelKey] = row; merged.push(row); continue; }
                for (const alt of row.alts)
                    if (!existing.alts.some(a => a.join(" ") === alt.join(" "))) existing.alts.push(alt);
            }
        }
        for (const row of merged) {
            row.alts = collapseArrows(row.alts);
            row.search = [row.group, row.section, row.label].concat(row.alts.map(a => a.join(" "))).join(" ").toLowerCase();
        }
        rows = merged;
    }

    function normaliseSubmap(name) {
        const trimmed = String(name ?? "").trim();
        return trimmed === "default" || trimmed === "reset" ? "" : trimmed;
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") root.submap = root.normaliseSubmap(event.data);
            else if (event.name === "configreloaded") root.refresh();
        }
    }

    Process {
        id: bindsProc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector { onStreamFinished: root.ingest(text) }
    }

    // The submap event only fires on a change, so a shell restarted mid-submap asks once.
    Process {
        id: submapProc
        command: ["hyprctl", "submap"]
        // anything but a bare name is hyprctl reporting an error, not a submap
        stdout: StdioCollector { onStreamFinished: if (/^\S+$/.test(text.trim())) root.submap = root.normaliseSubmap(text) }
    }

    Component.onCompleted: {
        refresh();
        submapProc.running = true;
    }
}
