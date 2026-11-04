import QtQuick 2.15
import "."
import "Titles.js" as Titles

// What a game shows where its art would be until it has some: its initials on
// a tile tinted with its system's colour.
Rectangle {
    id: root

    property string title: ""
    property string system: ""
    property real size: Theme.px(32)

    readonly property color hue: Theme.hue(system)

    width: size
    height: size
    radius: Math.max(Theme.px(6), size * 0.24)
    color: Theme.mix(Theme.bg0, hue, 0.2)
    antialiasing: true

    Label {
        anchors.centerIn: parent
        text: Titles.initials(root.title)
        color: root.hue
        font.pixelSize: root.size * 0.38
        font.weight: Font.DemiBold
        font.letterSpacing: -root.size * 0.01
    }
}
