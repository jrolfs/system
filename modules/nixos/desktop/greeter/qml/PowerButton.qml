import QtQuick

// A capsule on the login screen's power row. The first click only arms it,
// and the second within a few seconds acts: a trackpad on the sofa brushes
// past these more easily than a mouse on a desk.
Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property string confirm: ""
    property real u: 1

    signal activated()

    property bool armed: false
    readonly property bool hovered: mouse.containsMouse

    implicitWidth: content.implicitWidth + 32 * u
    implicitHeight: 38 * u
    radius: height / 2

    color: armed ? Qt.rgba(Colors.red.r, Colors.red.g, Colors.red.b, 0.22)
         : hovered ? Qt.rgba(Colors.fg1.r, Colors.fg1.g, Colors.fg1.b, 0.12)
         : Qt.rgba(Colors.bg0.r, Colors.bg0.g, Colors.bg0.b, 0.45)
    border.width: 1
    border.color: armed ? Qt.rgba(Colors.red.r, Colors.red.g, Colors.red.b, 0.5)
                : Qt.rgba(Colors.fg1.r, Colors.fg1.g, Colors.fg1.b, 0.12)

    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on border.color { ColorAnimation { duration: 140 } }
    Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    readonly property color ink: armed ? Colors.red
                               : hovered ? Colors.fg1
                               : Qt.rgba(Colors.fg0.r, Colors.fg0.g, Colors.fg0.b, 0.72)

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 8 * root.u

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.icon
            size: 16 * root.u
            color: root.ink
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.armed ? root.confirm : root.label
            font.family: "Geist"
            font.weight: 500
            font.pixelSize: 14 * root.u
            color: root.ink
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.armed) {
                root.armed = false;
                disarm.stop();
                root.activated();
            } else {
                root.armed = true;
                disarm.restart();
            }
        }
    }

    Timer {
        id: disarm
        interval: 3500
        onTriggered: root.armed = false
    }
}
