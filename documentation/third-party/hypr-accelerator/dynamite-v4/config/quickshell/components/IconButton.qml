import QtQuick
import "../theme"

// Square icon button, glyph from the display/nerd font. Ghost by default: a glass
// tint shows up on hover/press. Set `icon` to a glyph string.
Rectangle {
    id: root

    property string icon: ""
    property real iconSize: Theme.iconSize
    property color iconColor: Theme.inkDim
    signal clicked()

    implicitWidth: iconSize + Theme.s3
    implicitHeight: iconSize + Theme.s3
    radius: Theme.rSm
    color: ma.containsPress ? Theme.glassHigh : ma.containsMouse ? Theme.glassLow : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }

    StyledText {
        anchors.centerIn: parent
        text: root.icon
        font.family: Theme.fontDisplay
        font.pixelSize: root.iconSize
        color: root.iconColor
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
