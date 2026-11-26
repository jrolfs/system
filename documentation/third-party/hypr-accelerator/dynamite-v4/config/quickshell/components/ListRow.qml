import QtQuick
import "../theme"

// Selectable/hoverable row. Glass tint on hover, stronger once selected, plus an
// accent marker on the leading edge of the selected one. Content goes in as children
// (inset by s3). Fires clicked()/entered().
Rectangle {
    id: root

    property bool selected: false
    readonly property bool hovered: ma.containsMouse
    signal clicked()
    signal entered()

    default property alias content: holder.data

    // Idle fill. Transparent by default (glass over the surface). Set it to an opaque
    // surface colour where rows gotta OCCLUDE each other, like an animated/filtered list,
    // so a reflowing row covers a fading one instead of the two texts smearing together.
    property color baseColor: "transparent"

    implicitHeight: Theme.s6 + Theme.s1
    radius: Theme.rSm
    color: baseColor

    // selected/hover tint, layered OVER the (maybe opaque) base so the row still occludes
    // its neighbours during reflow animations even when it's selected.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: root.selected ? Theme.glassHigh : root.hovered ? Theme.glassLow : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
    }

    Rectangle {
        width: 3
        height: parent.height * 0.5
        radius: 2
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 2
        color: Theme.accent
        visible: root.selected
    }

    Item {
        id: holder
        anchors.fill: parent
        anchors.leftMargin: Theme.s3
        anchors.rightMargin: Theme.s3
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        onEntered: root.entered()
    }
}
