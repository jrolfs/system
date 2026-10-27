import QtQuick
import "../theme"

// Generic toggle-mode status glyph: an icon inside a circle ring. ON → accent ring and
// icon; OFF → grey ring and icon with a diagonal strike. The ring/icon colour and the
// strike both animate on toggle (the strike grows out from / retracts to the centre).
// Drives the mode OSD (Night Light, Game Mode, ...). Set `icon` to any name in Icon.qml.
Item {
    id: root

    property string icon: ""
    property bool on: false
    property real size: 16

    implicitWidth: size
    implicitHeight: size

    readonly property color tint: on ? Theme.accent : Theme.inkDim

    // circle ring
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: 1.5
        border.color: root.tint
        antialiasing: true
        Behavior on border.color { ColorAnimation { duration: Theme.dur(Theme.dEffects) } }
    }

    // mode icon
    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: Math.round(root.size * 0.58)
        color: root.tint
        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dEffects) } }
    }

    // diagonal strike: grows out from the centre when OFF, retracts when ON
    Rectangle {
        anchors.centerIn: parent
        height: 2.5
        radius: 1.25
        antialiasing: true
        rotation: -45
        transformOrigin: Item.Center
        width: root.on ? 0 : root.size
        color: root.tint
        Behavior on width { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dEffects) } }
    }
}
