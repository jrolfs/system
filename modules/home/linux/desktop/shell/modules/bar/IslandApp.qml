import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../theme"
import "../../components"

// The focused app, above the workspace capsules in the expanded island: its icon and its
// name, nothing else. The icon is TINTED the way iOS 18 tints icons: colourised from its
// own luminance with one hue (the workspace hue), so a logo in six colours reads as part
// of the island instead of a sticker on it.
//
// Motion, in the capsules' own energy (their spring, their stagger): on entrance the icon
// drops in from above and settles with the overshoot, the name a stagger behind it. When
// the focused app CHANGES while the island is open, the header simply crossfades: the old
// icon and name fade out as the new ones fade in, in place. Two slots per part take turns
// so the old and the new are both on screen for the fade.
Item {
    id: root

    property bool present: false
    property color tone: Theme.hue("workspaces")
    property real maxW: 128
    property int iconSize: 18
    // the entrance's gap between the icon and the name: wide enough to READ as two beats
    // (the capsules' 40ms gap between neighbours made the two land as one), each part on
    // the shorter base clock so the pair is still over before the capsules settle
    property int stagger: Math.round(Theme.stagger * 1.3)

    implicitWidth: row.width
    implicitHeight: Math.max(iconSize, na.implicitHeight)
    width: implicitWidth
    height: implicitHeight

    // ── what is focused ──
    // Focus comes from Hyprland's own events, not Quickshell's activeToplevel: that one
    // never goes null when an empty workspace takes focus (logged: "activewindow ," came
    // in, activeToplevel kept the old window), so the header named a window that was not
    // there. activewindowv2 carries the focused address, empty for nothing; activewindow
    // carries "class,title", which also names the app when the toplevel model lags.
    // Before the first event (right after a launch) the model's `activated` flag, then
    // hyprctl's focusHistoryID (0 on the focused window), stand in.
    //
    // And focus is not always something you can see: closing a special workspace over an
    // EMPTY workspace sends only "activespecial ," and leaves Hyprland's keyboard focus on
    // the special's now-hidden window (logged: Spotify, special down, no focus event,
    // `hyprctl activewindow` still Spotify), so the header named a window that was not on
    // screen. `specials` tracks what each monitor shows (activespecial events, seeded from
    // hyprctl monitors); a focused window on a special nobody shows counts as nothing.
    property int rev: 0
    property var specials: ({})
    property string truthWs: ""
    // the confirm is a snapshot taken a beat ago: a focus event that lands while it is in
    // flight is newer than its answer, so the answer's focus part is dropped (the specials
    // part is still taken), and a confirm asked for while one runs is run again after
    property int focusSeq: 0
    property int truthSeq: 0
    property bool reconfirm: false
    property bool liveFocus: false
    property string focusAddr: ""
    property string focusClass: ""
    function norm(a) { a = String(a ?? ""); return a.startsWith("0x") ? a.slice(2) : a; }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            const n = ev.name, d = String(ev.data ?? "");
            if (n === "activewindowv2") { root.focusAddr = root.norm(d.trim()); root.liveFocus = true; root.focusSeq++; }
            else if (n === "activewindow") { const i = d.indexOf(","); root.focusClass = (i >= 0 ? d.slice(0, i) : d).trim(); root.liveFocus = true; root.focusSeq++; }
            // a workspace change out from under a special workspace sends NO focus event
            // at all (logged: special up, jump to an empty workspace: only "workspace 3"),
            // so after anything that moves workspaces around, ask Hyprland what is focused
            if (n === "activespecial") { const i = d.indexOf(","); const s = Object.assign({}, root.specials); s[d.slice(i + 1).trim()] = d.slice(0, Math.max(i, 0)).trim(); root.specials = s; }
            if (n === "workspace" || n === "activespecial" || n === "focusedmon") confirm.restart();
            if (n === "activewindow" || n === "activewindowv2" || n === "openwindow" || n === "closewindow" || n === "workspace") root.rev++;
        }
    }
    Timer { id: confirm; interval: 80; onTriggered: root.askTruth() }
    function askTruth() {
        if (truth.running) { reconfirm = true; return; }
        truthSeq = focusSeq;
        truth.running = true;
    }
    Process {
        id: truth
        command: ["sh", "-c", "hyprctl activewindow -j; echo; echo @@; hyprctl monitors -j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("@@");
                let o = null, mons = null;
                try { o = JSON.parse(parts[0]); mons = JSON.parse(parts[1] ?? "[]"); } catch (e) { return; }
                if (root.focusSeq === root.truthSeq) {
                    if (o && o.address) { root.focusAddr = root.norm(o.address); root.focusClass = o.class || ""; root.truthWs = (o.workspace && o.workspace.name) || ""; }
                    else { root.focusAddr = ""; root.focusClass = ""; root.truthWs = ""; }
                }
                const s = {};
                for (const m of (Array.isArray(mons) ? mons : [])) s[m.name] = (m.specialWorkspace && m.specialWorkspace.name) || "";
                root.specials = s;
                root.liveFocus = true;
                root.rev++;
                if (root.reconfirm) { root.reconfirm = false; confirm.restart(); }
            }
        }
    }
    readonly property var focusedRaw: {
        rev;
        const m = Hyprland.toplevels;
        const all = m ? (m.values !== undefined ? m.values : m) : [];
        if (liveFocus) {
            if (focusAddr === "") return null;
            // no stale fallback here: when the model has no toplevel at this address yet,
            // `cls` takes the class the event named instead
            return all.find(t => root.norm(t.address) === focusAddr) ?? null;
        }
        return Hyprland.activeToplevel ?? all.find(t => t.activated) ?? all.find(t => t.lastIpcObject && t.lastIpcObject.focusHistoryID === 0) ?? null;
    }
    // the focused window's workspace: from the model, else what hyprctl last said
    readonly property string focusWs: {
        const t = root.focusedRaw;
        if (!t) return truthWs;
        if (t.workspace && t.workspace.name) return t.workspace.name;
        const o = t.lastIpcObject;
        return (o && o.workspace && o.workspace.name) ? o.workspace.name : truthWs;
    }
    readonly property bool hidden: {
        const n = root.focusWs;
        if (!n.startsWith("special:")) return false;
        for (const k in root.specials) if (root.specials[k] === n) return false;
        return true;
    }
    readonly property var focused: hidden ? null : focusedRaw
    readonly property string cls: {
        const t = root.focused;
        if (!t) return (liveFocus && focusAddr !== "" && !hidden) ? focusClass : "";
        const o = t.lastIpcObject;
        return (o && o.class) ? o.class : (t.wayland && t.wayland.appId ? t.wayland.appId : focusClass);
    }
    // reads the applications list so the lookup re-runs once the entries have loaded:
    // right after a launch it came back empty and the header said "Brave-browser" until
    // the next focus change said "Brave"
    readonly property var entry: { DesktopEntries.applications; return cls !== "" ? DesktopEntries.heuristicLookup(cls) : null; }
    // no desktop entry: the class, with a capital so it reads as a name
    readonly property string appName: entry ? entry.name : (cls !== "" ? cls.charAt(0).toUpperCase() + cls.slice(1) : "Desktop")
    readonly property string iconSrc: cls !== "" ? Quickshell.iconPath((entry && entry.icon) ? entry.icon : cls, "application-x-executable") : ""

    // ── entrance: two clocks 0..1, the icon's, then the name's a stagger later ──
    property real tIcon: 0
    property real tName: 0
    onPresentChanged: {
        if (present) { showNow(); enter.restart(); }
        else { enter.stop(); tIcon = 0; tName = 0; }
    }
    ParallelAnimation {
        id: enter
        NumberAnimation { target: root; property: "tIcon"; from: 0; to: 1; duration: Theme.dur(Theme.dBase); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
        SequentialAnimation {
            PauseAnimation { duration: Theme.dur(root.stagger) }
            NumberAnimation { target: root; property: "tName"; from: 0; to: 1; duration: Theme.dur(Theme.dBase); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
        }
    }

    // ── the crossfade on a focus change ──
    // Each part has two slots that alternate: the shown one carries what the header says,
    // the other takes the new value and fades in while the shown one fades out.
    property bool iconA: true
    property bool nameA: true
    function showNow() {            // no roll: write straight into the shown slots
        (iconA ? ia : ib).source = root.iconSrc;
        (nameA ? na : nb).text = root.appName;
    }
    Component.onCompleted: { showNow(); askTruth(); }
    // A focus change arrives as a burst, not a value: a window opening goes "nothing
    // focused" then the app within the same millisecond, the ipc class can replace the
    // wayland app id a moment later, and a desktop entry can resolve late and rename the
    // app (logged: Desktop -> Alacritty in 1ms; Brave-browser -> Brave on the way back).
    // Every hop restarted the fade, so the name visibly changed twice. The value settles
    // for a beat and the header fades ONCE to wherever it landed, and only if that
    // differs from what it shows.
    Timer { id: settle; interval: 120; onTriggered: root.commit() }
    onIconSrcChanged: settle.restart()
    onAppNameChanged: settle.restart()
    function commit() {
        if (!present) { showNow(); return; }
        const shownIcon = iconA ? ia : ib;
        if (String(shownIcon.source) !== root.iconSrc) {
            (iconA ? ib : ia).source = root.iconSrc;
            iconRoll.restart();
        }
        const shownName = nameA ? na : nb;
        if (shownName.text !== root.appName) {
            (nameA ? nb : na).text = root.appName;
            nameRoll.restart();
        }
    }
    SequentialAnimation {
        id: iconRoll
        ParallelAnimation {
            NumberAnimation { target: root.iconA ? ia : ib; property: "opacity"; to: 0; duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
            NumberAnimation { target: root.iconA ? ib : ia; property: "opacity"; to: 1; duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
        }
        ScriptAction { script: root.iconA = !root.iconA }
    }
    SequentialAnimation {
        id: nameRoll
        ParallelAnimation {
            NumberAnimation { target: root.nameA ? na : nb; property: "opacity"; to: 0; duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
            NumberAnimation { target: root.nameA ? nb : na; property: "opacity"; to: 1; duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
        }
        // flip, then empty the slot that just left so it never props the box's width
        ScriptAction { script: { root.nameA = !root.nameA; (root.nameA ? nb : na).text = ""; } }
    }

    // one tinted icon slot
    component Slot: Item {
        property alias source: img.source
        width: root.iconSize; height: root.iconSize
        Image {
            id: img
            anchors.fill: parent
            sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
            asynchronous: true
            visible: false
            layer.enabled: true
        }
        MultiEffect {
            anchors.fill: parent
            source: img
            // colorization alone: it already works from the pixel's luminance, and
            // MultiEffect applies saturation AFTER it, so saturation -1 drained the tint
            // back to gray (seen: a gray icon with the colour set to pure red)
            colorization: 1.0
            colorizationColor: root.tone
            visible: img.status === Image.Ready && img.source.toString() !== ""
        }
        // nothing focused: a quiet dot where the icon would be
        Rectangle {
            anchors.centerIn: parent
            width: 6; height: 6; radius: 3
            color: Theme.alpha(root.tone, 0.4)
            visible: img.source.toString() === ""
        }
    }
    // one name slot
    component NameSlot: StyledText {
        width: Math.min(implicitWidth, root.maxW - root.iconSize - row.spacing)
        font.pixelSize: Theme.fsLabel
        font.weight: Theme.wMedium
        color: Theme.inkPrimary
        elide: Text.ElideRight
    }

    Row {
        id: row
        spacing: 8

        Item {
            id: iconBox
            width: root.iconSize; height: root.iconSize
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.tIcon
            transform: Translate { y: (1 - root.tIcon) * -10 }
            Slot { id: ia }
            Slot { id: ib; opacity: 0 }
        }

        Item {
            id: nameBox
            width: Math.max(na.width, nb.width)
            height: na.implicitHeight
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.tName
            transform: Translate { y: (1 - root.tName) * -10 }
            NameSlot { id: na }
            NameSlot { id: nb; opacity: 0 }
        }
    }
}
