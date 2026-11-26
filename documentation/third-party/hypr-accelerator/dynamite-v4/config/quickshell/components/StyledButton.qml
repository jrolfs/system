import QtQuick
import "../theme"

// Text button. `variant`: "ghost" (hairline + glass hover) or "accent" (filled, for
// the one primary action). Accent paints onAccent ink so it reads in every scheme.
Rectangle {
    id: root

    property string text: ""
    property string variant: "ghost"   // ghost | accent
    signal clicked()

    readonly property bool isAccent: variant === "accent"

    implicitWidth: label.implicitWidth + Theme.s4 * 2
    implicitHeight: label.implicitHeight + Theme.s3
    radius: Theme.rSm

    color: isAccent
        ? (ma.containsPress ? Theme.accentDeep : Theme.accent)
        : (ma.containsPress ? Theme.glassHigh : ma.containsMouse ? Theme.glassLow : "transparent")
    border.width: isAccent ? 0 : 1
    border.color: Theme.hairline
    Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }

    StyledText {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.isAccent ? Theme.onAccent : Theme.inkPrimary
        font.weight: Theme.wMedium
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
