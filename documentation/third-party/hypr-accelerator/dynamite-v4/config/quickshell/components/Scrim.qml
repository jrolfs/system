import QtQuick
import "../theme"
import "../config"

// Dim backdrop for overlays/auth. The blur-behind is handled by the Hyprland layerrule
// on the surface's namespace; this here is just the dim veil plus click-to-dismiss,
// fading in. Sits behind a centered card.
Rectangle {
    id: root

    property real dim: Config.scrimOpacity / 100
    signal clicked()

    color: Qt.rgba(0, 0, 0, dim)   // neutral black dim on every scheme: a shadow, not a surface
    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dBase); easing.type: Theme.easeOut } }

    MouseArea { anchors.fill: parent; onClicked: root.clicked() }
}
