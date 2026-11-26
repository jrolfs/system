import QtQuick
import "../../theme"
import "LayoutRegion.js" as LayoutRegion

// A thumbnail of the screen with the region a window-mode bind puts the window in, Moom's
// icon beside each action. A label that names no region draws an empty space of the same
// size, so the labels beside it stay in line.
Item {
    id: root

    property string label: ""
    readonly property var region: LayoutRegion.region(label)

    implicitWidth: 22
    implicitHeight: 16

    Rectangle {
        anchors.fill: parent
        visible: root.region !== null
        radius: 3
        color: "transparent"
        border.width: 1
        border.color: Theme.keycapEdge

        Rectangle {
            readonly property real inset: 2
            x: inset + (root.region?.x ?? 0) * (parent.width - inset * 2)
            y: inset + (root.region?.y ?? 0) * (parent.height - inset * 2)
            width: Math.max(2, (root.region?.w ?? 0) * (parent.width - inset * 2))
            height: Math.max(2, (root.region?.h ?? 0) * (parent.height - inset * 2))
            radius: 1.5
            color: Theme.alpha(Theme.accent, 0.85)
        }
    }
}
