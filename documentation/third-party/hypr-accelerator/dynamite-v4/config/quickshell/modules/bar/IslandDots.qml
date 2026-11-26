import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import "../../theme"

// Workspaces as capsules: small pills, the active one the same pill scaled up (never
// wider: a width change reflows the row; a scale does not). State is brightness in ONE
// colour, not hue. Occupied ones carry ink, empty ones only a trace. A workspace that
// appears fades in; one that goes fades out. Scroll over them to move between them,
// click one to go there.
//
// ONE set of capsules with TWO homes. At rest they sit in the pill, left of the time; in
// the open island they sit in the left column, a size up. Each capsule owns a clock `t`
// between the two and glides from one home to the other on its own spring, one capsule
// after another, so the row visibly travels from the centre to the left and back instead
// of one set vanishing and another popping up. The parent gives both homes in ITS
// coordinate space (this item fills the parent); the overshoot of the spring is the
// settle.
Item {
    id: root

    required property var screen
    property bool open: false        // which home is current
    property bool restOn: true       // the rest home is wanted at all (pill capsules enabled)
    property bool openOn: true       // the open home is wanted at all
    // the rest home: left edge x, centre line y, capsule size, gap
    property real restX: 0
    property real restY: 0
    property real restCapW: 7
    property real restCapH: 12
    property real restGap: 5
    // the open home
    property real openX: 0
    property real openY: 0
    property real openCapW: 9
    property real openCapH: 17
    property real openGap: 7
    property real activeScale: 1.3   // the active one is the same pill, scaled up about its centre
    // one capsule after another, fast; the whole row leaves within ~220ms however many
    // there are (ten at the five-capsule gap left the last ones waiting under the time)
    property int stagger: Math.round(Math.min(Theme.stagger * 0.45, 220 / Math.max(1, count)))

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    // regular workspaces on THIS monitor, by id. Special/scratchpad ones (negative id) are
    // toggled, not switched to, so they would mislead as dots.
    readonly property var list: {
        const mon = root.monitor;
        if (!mon) return [];
        return Hyprland.workspaces.values
            .filter(w => w.id > 0 && w.monitor && w.monitor.id === mon.id)
            .sort((a, b) => a.id - b.id);
    }
    readonly property int count: list.length
    readonly property int activeId: (monitor && monitor.activeWorkspace) ? monitor.activeWorkspace.id : -1
    // the row's settled width in each home, for whoever lays the homes out
    readonly property real restW: count > 0 ? count * restCapW + (count - 1) * restGap : 0
    readonly property real openW: count > 0 ? count * openCapW + (count - 1) * openGap : 0

    // Occupancy comes from the LIVE toplevel model, not the workspace's cached ipc object.
    // That object only refreshes when Quickshell re-reads the workspace list, so a window
    // opened on an empty workspace, or the last one closed, left the capsule's tone stale
    // until a reload (measured: `lastIpcObject.windows` sat at the old count through an
    // open and a close while the toplevel model moved 7 -> 8 -> 7). Every count reads
    // through `rev`, which the raw event stream bumps on anything that adds, removes or
    // moves a window.
    property int rev: 0
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            const n = ev.name;
            if (n === "openwindow" || n === "closewindow" || n === "movewindow" || n === "movewindowv2" || n === "moveworkspace") root.rev++;
        }
    }
    function windowsOn(id) {
        rev;
        const m = Hyprland.toplevels;
        const all = m ? (m.values !== undefined ? m.values : m) : [];
        let c = 0;
        for (const t of all) if (t.workspace && t.workspace.id === id) c++;
        return c;
    }

    function go(id) { Hyprland.dispatch(`hl.dsp.focus({ workspace = ${id} })`); }
    function step(dir) {
        const ids = root.list.map(w => w.id);
        const i = ids.indexOf(root.activeId);
        const n = i < 0 ? 0 : Math.max(0, Math.min(ids.length - 1, i + dir));
        if (ids.length && ids[n] !== root.activeId) go(ids[n]);
    }
    // one step per notch, with a short cooldown so a flick doesn't skip across the row
    Timer { id: cool; interval: 140 }
    function wheel(ev) {
        if (cool.running) return;
        const d = ev.angleDelta.y !== 0 ? ev.angleDelta.y : ev.angleDelta.x;
        if (d === 0) return;
        root.step(d < 0 ? 1 : -1);
        cool.restart();
    }

    Repeater {
        model: root.list
        delegate: Rectangle {
            id: dot
            required property var modelData
            required property int index
            readonly property bool active: modelData.id === root.activeId
            readonly property color tone: Theme.hue("workspaces")
            readonly property int windows: root.windowsOn(modelData.id)
            readonly property bool occupied: windows > 0

            // 0 = at rest in the pill, 1 = in the open island. Travels on its own spring,
            // this capsule's turn coming `stagger` after the one before it (and in the
            // reverse order on the way home, so the row retracts from its far end).
            property real t: 0
            Component.onCompleted: { t = root.open ? 1 : 0; entered = 1; }
            Connections {
                target: root
                function onOpenChanged() { glide.restart(); }
            }
            SequentialAnimation {
                id: glide
                PauseAnimation { duration: Theme.dur(root.stagger) * (root.open ? dot.index : (root.count - 1 - dot.index)) }
                NumberAnimation { target: dot; property: "t"; to: root.open ? 1 : 0; duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
            }
            function mix(a, b) { return a + (b - a) * t; }

            width: mix(root.restCapW, root.openCapW)
            height: mix(root.restCapH, root.openCapH)
            x: mix(root.restX + index * (root.restCapW + root.restGap), root.openX + index * (root.openCapW + root.openGap))
            y: mix(root.restY, root.openY) - height / 2
            radius: height / 2      // a true pill at every width
            color: active ? dot.tone : occupied ? Theme.alpha(dot.tone, 0.42) : Theme.alpha(dot.tone, 0.16)
            antialiasing: true
            Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }

            // delegate-owned entrance (patterns.md #5), times the homes that are wanted:
            // a home that is off fades the capsule out on the way there
            property real entered: 0
            Behavior on entered { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
            readonly property real tc: Math.max(0, Math.min(1, t))
            opacity: entered * ((root.restOn ? 1 - tc : 0) + (root.openOn ? tc : 0))
            visible: opacity > 0.01
            transformOrigin: Item.Center
            scale: active ? root.activeScale : (ma.containsMouse ? 1.1 : 1)
            Behavior on scale { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }

            // the glow: a blurred accent copy behind the active capsule
            layer.enabled: active && Theme.shadows
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Theme.alpha(dot.tone, 0.85)
                shadowBlur: 1.0
                blurMax: 14
                shadowVerticalOffset: 0
                shadowOpacity: 0.9
                autoPaddingEnabled: true
            }

            MouseArea {
                id: ma
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.go(dot.modelData.id)
                onWheel: ev => root.wheel(ev)
            }
        }
    }
}
