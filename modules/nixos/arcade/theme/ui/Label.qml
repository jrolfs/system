import QtQuick 2.15
import "."

// Text on the shell's type scale (components/StyledText.qml). `variant` picks
// the role; an explicit font.pixelSize or color still wins.
Text {
    // display | title | header | body | label | caption
    property string variant: "body"

    color: Theme.inkPrimary
    font.family: Theme.fontBody
    font.pixelSize: variant === "display" ? Theme.fsDisplay
        : variant === "title" ? Theme.fsTitle
        : variant === "header" ? Theme.fsHeader
        : variant === "label" ? Theme.fsLabel
        : variant === "caption" ? Theme.fsCaption
        : Theme.fsBody
    // Qt 5 weights run 0–99, where the shell's Qt 6 ones run 100–900.
    font.weight: variant === "display" || variant === "title" || variant === "header" ? Font.Medium : Font.Normal
    font.letterSpacing: variant === "header" ? Theme.headerTracking : 0
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
}
