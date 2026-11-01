import QtQuick
import "../theme"

// Controlled horizontal slider. `value` is driven by the owner (bind it to a service
// property); a drag emits `moved(value)`. Do NOT bind value two-way: route `moved` to
// the service setter instead, or yer gonna get a feedback loop.
Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0
    signal moved(real value)

    implicitWidth: 200
    implicitHeight: 18

    readonly property real ratio: to === from ? 0 : Math.max(0, Math.min(1, (value - from) / (to - from)))

    function applyAt(px) {
        const r = Math.max(0, Math.min(1, px / width));
        root.moved(from + r * (to - from));
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: Theme.rPill
        color: Theme.glassHigh

        Rectangle {
            width: parent.width * root.ratio
            height: parent.height
            radius: parent.radius
            color: Theme.accent
        }
    }

    Rectangle {
        width: 16
        height: 16
        radius: Theme.rPill
        anchors.verticalCenter: parent.verticalCenter
        x: (root.width - width) * root.ratio
        color: ma.pressed ? Theme.accentDeep : Theme.inkPrimary
        border.color: Theme.accent
        border.width: 2
        scale: ma.pressed ? 1.15 : 1
        Behavior on scale { NumberAnimation { duration: Theme.dur(Theme.dFast); easing.type: Theme.easeOut } }
    }

    // Hit area, deliberately TALLER than the 6px track: grabbing a slider shouldn't need
    // pixel-accurate aim at a hairline. Extends `grab` px above and below the item (a
    // MouseArea may spill past its parent as long as nothing clips it), so the whole band
    // around the track drags. Also takes the wheel, so you can nudge a value by scrolling
    // anywhere over that band instead of dragging the handle.
    readonly property int grab: 11
    readonly property real wheelStep: (to - from) / 25

    MouseArea {
        id: ma
        anchors.fill: parent
        anchors.topMargin: -root.grab
        anchors.bottomMargin: -root.grab
        cursorShape: Qt.PointingHandCursor
        onPressed: root.applyAt(mouseX)
        onPositionChanged: if (pressed) root.applyAt(mouseX)
        // consumed here (not left to the page), so a scroll over a slider tunes it
        onWheel: (wheel) => {
            const dy = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y;
            if (dy === 0) return;
            const next = root.value + (dy > 0 ? root.wheelStep : -root.wheelStep);
            root.moved(Math.max(root.from, Math.min(root.to, next)));
        }
    }
}
