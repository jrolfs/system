import QtQuick
import "../theme"

// One key in a shortcut hint, the way Raycast draws them: a small outlined rounded square
// with the glyph inside (↵, ⌘, K, esc). Wider keys grow sideways and stay the same height.
Rectangle {
    id: root

    property string text: ""

    implicitHeight: 22
    implicitWidth: Math.max(implicitHeight, label.implicitWidth + 12)
    radius: 6
    color: "transparent"
    border.width: 1
    border.color: Theme.keycapEdge

    StyledText {
        id: label
        anchors.centerIn: parent
        text: root.text
        font.pixelSize: Theme.fsCaption
        font.weight: Theme.wMedium
        color: Theme.keycapInk
    }
}
