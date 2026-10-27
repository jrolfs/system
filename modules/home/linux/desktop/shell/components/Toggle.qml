import QtQuick
import "../theme"

// Pill switch. Controlled, so bind `checked` and handle `toggled(value)` yourself.
Rectangle {
    id: root

    property bool checked: false
    signal toggled(bool value)

    implicitWidth: 44
    implicitHeight: 24
    radius: Theme.rPill
    color: checked ? Theme.accent : Theme.glassHigh
    Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }

    Rectangle {
        width: 18
        height: 18
        radius: 9
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 3 : 3
        color: root.checked ? Theme.onAccent : Theme.inkDim
        Behavior on x { NumberAnimation { duration: Theme.dur(Theme.dFast); easing.type: Theme.easeOut } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
