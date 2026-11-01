import QtQuick
import QtQuick.Shapes
import "../../theme"
import "../../config"
import "../../services"
import "../../components"

// The inbox, above the status glyphs in the expanded island's right column: the mirror
// of the focused app on the left. One line of text and a bell on its outer side, the
// bell tinted with the notifications hue the way the app icon wears the workspace hue.
// "All caught up" when there is nothing, the count when there is, and "Focus on" under
// a moon while do-not-disturb holds.
//
// Motion mirrors the left: on entrance the bell (the outer part) drops in first and the
// text follows a stagger behind; when the text or the icon changes while the island is
// open, that part crossfades in place through two alternating slots.
Item {
    id: root

    property bool present: false
    property color tone: Theme.hue("notifications")
    property real maxW: 128
    property int iconSize: 18
    property int stagger: Math.round(Theme.stagger * 1.3)

    implicitWidth: row.width
    implicitHeight: Math.max(iconSize, ta.implicitHeight)
    width: implicitWidth
    height: implicitHeight

    readonly property int count: Notifications.list.length
    readonly property bool quiet: GlobalState.dnd
    readonly property string label: quiet ? "Focus on" : count === 0 ? "All caught up" : (count === 1 ? "1 notification" : count + " notifications")
    readonly property string glyph: quiet ? "night" : "bell"

    // ── entrance: two clocks 0..1, the bell's, then the text's a stagger later ──
    property real tIcon: 0
    property real tText: 0
    onPresentChanged: {
        if (present) { showNow(); enter.restart(); }
        else { enter.stop(); tIcon = 0; tText = 0; }
    }
    ParallelAnimation {
        id: enter
        NumberAnimation { target: root; property: "tIcon"; from: 0; to: 1; duration: Theme.dur(Theme.dBase); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
        SequentialAnimation {
            PauseAnimation { duration: Theme.dur(root.stagger) }
            NumberAnimation { target: root; property: "tText"; from: 0; to: 1; duration: Theme.dur(Theme.dBase); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
        }
    }

    // ── the crossfade on a change ──
    property bool textA: true
    property bool iconA: true
    function showNow() { (textA ? ta : tb).text = root.label; (iconA ? ia : ib).name = root.glyph; }
    Component.onCompleted: showNow()
    Timer { id: settle; interval: 120; onTriggered: root.commit() }
    onLabelChanged: settle.restart()
    onGlyphChanged: settle.restart()
    function commit() {
        if (!present) { showNow(); return; }
        if ((textA ? ta : tb).text !== root.label) {
            (textA ? tb : ta).text = root.label;
            roll.restart();
        }
        if ((iconA ? ia : ib).name !== root.glyph) {
            (iconA ? ib : ia).name = root.glyph;
            iconRoll.restart();
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
        id: roll
        ParallelAnimation {
            NumberAnimation { target: root.textA ? ta : tb; property: "opacity"; to: 0; duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
            NumberAnimation { target: root.textA ? tb : ta; property: "opacity"; to: 1; duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
        }
        ScriptAction { script: { root.textA = !root.textA; (root.textA ? tb : ta).text = ""; } }
    }

    // one icon slot. Geometry renderer: the curve one draws stroked icons as nothing on
    // some launches (patterns.md 61); samples for the antialiasing it lacks
    component Glyph: Icon {
        anchors.centerIn: parent
        size: root.iconSize
        color: root.tone
        renderer: Shape.GeometryRenderer
        layer.enabled: true
        layer.samples: 4
    }
    component TextSlot: StyledText {
        // right-aligned in the box so a shorter label keeps its edge against the bell
        anchors.right: parent.right
        width: Math.min(implicitWidth, root.maxW - root.iconSize - row.spacing)
        font.pixelSize: Theme.fsLabel
        font.weight: Theme.wMedium
        color: Theme.inkPrimary
        elide: Text.ElideLeft
    }

    Row {
        id: row
        spacing: 8

        Item {
            id: textBox
            width: Math.max(ta.width, tb.width)
            height: ta.implicitHeight
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.tText
            transform: Translate { y: (1 - root.tText) * -10 }
            TextSlot { id: ta }
            TextSlot { id: tb; opacity: 0 }
        }

        Item {
            width: root.iconSize; height: root.iconSize
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.tIcon
            transform: Translate { y: (1 - root.tIcon) * -10 }
            // two slots that take turns, like the text's
            Glyph { id: ia }
            Glyph { id: ib; opacity: 0 }
        }
    }
}
