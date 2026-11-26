import QtQuick
import "../../theme"
import "../../components"

// Shared pieces for the connectivity sheets: a section label with an optional live
// "scanning" pulse at its right, a small ghost action chip, and the round icon disc rows
// are built from. Kept together so the Wi-Fi and Bluetooth sheets read as one design.
Item {
    id: bits
    visible: false

    // "NETWORKS  ........  • Scanning": the pulse is a real animation while `busy` is on, and
    // is held still under reduced motion (a 0ms loop would spin the CPU).
    component SectionLabel: Item {
        property string text: ""
        property bool busy: false
        property string busyText: "Scanning"
        width: parent ? parent.width : 0
        height: 18
        StyledText { anchors.left: parent.left; capCentreIn: parent; variant: "caption"; text: parent.text; color: Theme.inkFaint }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.s2
            visible: parent.busy
            Rectangle {
                id: pulse
                anchors.verticalCenter: parent.verticalCenter
                width: 6; height: 6; radius: 3
                color: Theme.hue("toggles")
                SequentialAnimation on opacity {
                    running: pulse.visible && Theme.dur(Theme.dSpring) > 0
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                }
            }
            StyledText { anchors.verticalCenter: parent.verticalCenter; variant: "caption"; text: parent.parent.busyText; color: Theme.inkDim }
        }
    }

    // a quiet pill with a verb in it: "Connect", "Disconnect", "Pair", "Forget"
    component Chip: Rectangle {
        property string text: ""
        property bool accent: false
        property bool enabledLook: true
        property color tint: Theme.accent
        signal clicked()
        implicitWidth: chipText.implicitWidth + Theme.s3 * 2
        implicitHeight: 28
        radius: 14
        color: chipMa.containsMouse ? Theme.fillHigh : Theme.fillLow
        opacity: enabledLook ? 1 : 0.45
        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
        StyledText { id: chipText; anchors.horizontalCenter: parent.horizontalCenter; capCentreIn: parent; variant: "caption"; font.weight: Theme.wMedium; text: parent.text; color: parent.accent ? parent.tint : Theme.inkPrimary }
        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: parent.enabledLook; onClicked: parent.clicked() }
    }

    // A compact slider for the sheets: sunken track, accent fill, the symbol at the left is
    // its own press target (mute / a sub-view). Same rules as the big slider cards: the fill
    // follows the POINTER while it owns the value (PipeWire and the brightness poll echo
    // late) and hands back once the backend catches up; clicks and external changes glide,
    // drags stay glued.
    component Track: Item {
        id: tk
        implicitHeight: 28              // so a wrapper can size to it (height alone is not implicit)
        property real value: 0          // 0..1 from the backend
        property color tint: Theme.accent
        property bool muted: false
        property string icon: ""
        property bool showPercent: true
        signal moved(real v)          // every frame the pointer owns the value (live consumers)
        signal released(real v)       // once, on drop/click: for consumers that commit on release
        signal iconClicked()
        width: parent ? parent.width : 0
        height: 28

        property real localRatio: -1
        readonly property real shown: localRatio >= 0 ? localRatio : Math.max(0, Math.min(1, value))
        onValueChanged: if (localRatio >= 0 && !tkMa.dragging && Math.abs(value - localRatio) < 0.015) localRatio = -1
        Timer { id: tkHold; interval: 1600; onTriggered: tk.localRatio = -1 }
        function own(r) { r = Math.max(0, Math.min(1, r)); localRatio = r; tkHold.restart(); tk.moved(r); }

        Rectangle {
            id: tkTrack
            anchors.left: parent.left
            anchors.right: pct.visible ? pct.left : parent.right
            anchors.rightMargin: pct.visible ? Theme.s2 : 0
            anchors.verticalCenter: parent.verticalCenter
            height: 28
            radius: Theme.rPill
            color: Theme.sunken
            Rectangle {
                id: tkFill
                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                width: Math.max(height, parent.width * tk.shown)
                radius: Theme.rPill
                color: tk.muted ? Theme.alpha(tk.tint, 0.35) : tk.tint
                opacity: tk.shown > 0 ? 1 : 0
                Behavior on width   { enabled: !tkMa.dragging; NumberAnimation { duration: Theme.dur(Theme.dBase); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }
                Behavior on color   { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
            }
            Icon {
                anchors.left: parent.left; anchors.leftMargin: Theme.s2 + 1
                anchors.verticalCenter: parent.verticalCenter
                visible: tk.icon !== ""
                name: tk.icon
                size: Theme.iconSize - 4
                color: tkFill.width > Theme.s2 + Theme.iconSize && !tk.muted ? Theme.onAccent : Theme.inkPrimary
                Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
            }
            MouseArea {
                id: tkMa
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                property bool iconPress: false
                property bool dragging: false
                property real pressX: 0
                onPressed: m => { iconPress = tk.icon !== "" && m.x < 32; dragging = false; pressX = m.x; if (!iconPress) tk.own(m.x / width); }
                onPositionChanged: m => { if (!pressed || iconPress) return; if (!dragging && Math.abs(m.x - pressX) < 3) return; dragging = true; tk.own(m.x / width); }
                onReleased: { if (!iconPress) tk.released(tk.shown); dragging = false; tkHold.restart(); }
                onCanceled: { dragging = false; tkHold.restart(); }
                onClicked: { if (iconPress) tk.iconClicked(); }
            }
        }
        StyledText {
            id: pct
            visible: tk.showPercent
            anchors.right: parent.right
            capCentreIn: parent
            width: 34
            horizontalAlignment: Text.AlignRight
            variant: "caption"
            text: Math.round(tk.shown * 100) + "%"
            color: Theme.inkDim
        }
    }

    // the icon disc at the left of a row: accent when the thing is live, quiet otherwise
    component Disc: Rectangle {
        property bool live: false
        property string icon: ""
        property int size: 32
        property color tint: Theme.accent
        width: size; height: size; radius: size / 2
        color: live ? tint : Theme.fillHigh
        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
        Icon { anchors.centerIn: parent; visible: parent.icon !== ""; name: parent.icon; size: parent.size >= 40 ? Theme.iconSize : Theme.iconSize - 4; color: parent.live ? Theme.onAccent : Theme.inkPrimary }
    }

    // ── things making room ──
    // Rows around one that turns up or leaves spring to their new places on the shell's own
    // curve. The ENTRANCE is never a positioner transition: `add` is cancelled by the next
    // relayout (a list folding, a label flipping visible) and strands the item at opacity 0,
    // which is how the Wi-Fi fold chip vanished while its 32px stayed. Rows own their fade
    // (`entered`, set in Component.onCompleted, behind a Behavior); labels, chips and
    // empty-state lines bind opacity to `visible` behind a Behavior, which retargets safely.
    // Only positioners whose children keep their size take `move`: on one whose child
    // animates its own height (the Wi-Fi list, the resolution picker) it restarts every
    // frame and chases.
    component MoveSpring: Transition {
        NumberAnimation { properties: "x,y"; duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
    }
}
