import QtQuick
import "../../theme"
import "../../components"

// Thick Material-You slider: a tall rounded track, accent fill growing from the left
// (clipped to the track's rounding) with an icon glyph inside. It's controlled, so bind
// `value` and route `moved(v)` to a service setter. Don't two-way bind it.
Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0
    property string icon: ""       // custom Icon name (the preferred path)
    property string glyph: ""      // old nerd-font fallback
    signal moved(real value)

    implicitWidth: 200
    implicitHeight: 44

    readonly property real ratio: to === from ? 0 : Math.max(0, Math.min(1, (value - from) / (to - from)))

    function applyAt(px) {
        const r = Math.max(0, Math.min(1, px / width));
        root.moved(from + r * (to - from));
    }

    Rectangle {
        id: track
        anchors.fill: parent
        radius: Theme.rPill          // fully rounded ends
        color: Theme.surfaceOverlay

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(height, parent.width * root.ratio)  // keep a round cap even when the value's low
            radius: Theme.rPill      // rounded fill cap
            color: Theme.accent
            visible: root.ratio > 0
        }
    }

    // icon sits over the fill on the left; flips to onAccent once the fill reaches it
    readonly property color iconInk: root.ratio > 0.13 ? Theme.onAccent : Theme.inkPrimary
    Icon {
        anchors.left: parent.left
        anchors.leftMargin: Theme.s4
        anchors.verticalCenter: parent.verticalCenter
        visible: root.icon !== ""
        name: root.icon
        color: root.iconInk
    }
    StyledText {
        anchors.left: parent.left
        anchors.leftMargin: Theme.s4
        capCentreIn: parent
        visible: root.icon === "" && root.glyph !== ""
        font.family: Theme.fontGlyph
        font.pixelSize: Theme.iconSize
        text: root.glyph
        color: root.iconInk
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: root.applyAt(mouseX)
        onPositionChanged: if (pressed) root.applyAt(mouseX)
    }
}
