import QtQuick
import "../../theme"
import "../../components"

// A bind's keys as separate caps, one per modifier plus the key (⌃ ⌥ 3), the way Raycast
// and Moom spell a shortcut. More than one way to press it reads "⌥ ⇧ 3 or ⌘ ⇧ 3".
Row {
    id: root

    // [["⌘", "Space"], ["Hyper", "?"]]
    property var alts: []

    spacing: Theme.s2

    Repeater {
        model: root.alts
        delegate: Row {
            id: alt
            required property var modelData
            required property int index
            spacing: Theme.s2

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: alt.index > 0
                variant: "caption"
                color: Theme.inkFaint
                text: "or"
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Repeater {
                    model: alt.modelData
                    delegate: Keycap {
                        required property string modelData
                        text: modelData
                    }
                }
            }
        }
    }
}
