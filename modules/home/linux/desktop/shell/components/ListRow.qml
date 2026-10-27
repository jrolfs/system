import QtQuick
import "../theme"

// Selectable, hoverable list row in the Raycast manner: no marker, just a lighter
// translucent fill across the row's width with soft corners, fainter on hover. Content
// goes in as children (inset by s3). Fires clicked()/entered().
Rectangle {
    id: root

    property bool selected: false
    readonly property bool hovered: ma.containsMouse
    signal clicked()
    signal entered()

    default property alias content: holder.data

    // Idle fill under the selection tint. Transparent so the glass reads through.
    property color baseColor: "transparent"

    implicitHeight: Theme.s6 + Theme.s1
    radius: Theme.rRow
    color: baseColor

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: root.selected ? Theme.selection
             : root.hovered ? Theme.alpha(Theme.foreground, Theme.selection.a / 2)
             : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
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
