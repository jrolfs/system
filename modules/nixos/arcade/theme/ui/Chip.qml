import QtQuick 2.15
import "."

// A small pill of fact about a game: a region, a revision, a genre.
Rectangle {
    id: root

    property alias text: label.text

    implicitHeight: Theme.px(26)
    implicitWidth: label.implicitWidth + 2 * Theme.s3
    radius: height / 2
    color: Theme.fillLow
    antialiasing: true

    Label {
        id: label
        anchors.centerIn: parent
        variant: "caption"
        font.weight: Font.Medium
        color: Theme.inkSecondary
    }
}
