import QtQuick 2.15
import "."

// An action and the buttons for it, as the shell's launcher footer reads:
// "Play ✕", "System L1 R1".
Row {
    id: root

    property string text: ""
    // Each { glyph: "cross" } or { text: "L1" }.
    property var keys: []

    spacing: Theme.s2

    Label {
        anchors.verticalCenter: parent.verticalCenter
        variant: "label"
        text: root.text
        color: Theme.inkDim
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.s1
        Repeater {
            model: root.keys
            Keycap {
                text: modelData.text || ""
                glyph: modelData.glyph || ""
            }
        }
    }
}
