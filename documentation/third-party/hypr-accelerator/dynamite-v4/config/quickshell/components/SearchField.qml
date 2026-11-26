import QtQuick
import "../theme"

// Glass search/text field. The inner TextInput is exposed as `input` so callers can
// drive focus; `text` is aliased. Accent hairline shows when it's focused.
Rectangle {
    id: root

    property alias text: input.text
    property alias input: input
    property string placeholder: "Search"
    signal accepted()

    implicitHeight: Theme.s6 + Theme.s1
    radius: Theme.rSm
    color: Theme.glassLow
    border.width: input.activeFocus ? 1 : 0
    border.color: Theme.accent

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: Theme.s3
        anchors.rightMargin: Theme.s3
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        color: Theme.inkPrimary
        selectionColor: Theme.alpha(Theme.accent, 0.4)
        font.family: Theme.fontBody
        font.pixelSize: Theme.fsBody
        onAccepted: root.accepted()
    }

    StyledText {
        anchors.left: input.left
        capCentreIn: parent
        text: root.placeholder
        color: Theme.inkFaint
        visible: input.text.length === 0
    }
}
