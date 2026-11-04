import QtQuick 2.15
import "."

// One button in a hint, the way the shell draws a key (components/Keycap.qml):
// a small outline with the label inside. Face buttons are round with their
// symbol, shoulders and triggers keep the shell's rounded square.
Rectangle {
    id: root

    property string text: ""
    property string glyph: ""

    implicitHeight: Theme.px(22)
    implicitWidth: glyph !== "" ? implicitHeight : Math.max(implicitHeight, label.implicitWidth + Theme.px(12))
    radius: glyph !== "" ? height / 2 : Theme.px(6)
    color: "transparent"
    border.width: Theme.hairlineWidth
    border.color: Theme.keycapEdge
    antialiasing: true

    Label {
        id: label
        visible: root.glyph === ""
        anchors.centerIn: parent
        text: root.text
        font.pixelSize: Theme.fsCaption
        font.weight: Font.Medium
        color: Theme.keycapInk
    }

    Glyph {
        visible: root.glyph !== ""
        anchors.centerIn: parent
        name: root.glyph
        size: root.height * 0.62
        color: Theme.keycapInk
    }
}
