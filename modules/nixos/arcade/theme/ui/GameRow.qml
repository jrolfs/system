import QtQuick 2.15
import "."
import "Titles.js" as Titles

// One game in the list, as the shell's launcher draws a result: its art or
// monogram, the title, a dim subtitle inline (the regions), and on the right
// a heart for a favorite and the year when it's known.
Item {
    id: root

    property var game: null
    property bool selected: false

    readonly property var parsed: Titles.parse(game ? game.title : "")
    readonly property string system: game && game.collections.count > 0 ? game.collections.get(0).shortName : ""
    readonly property string thumbnail: game ? game.assets.boxFront : ""

    implicitHeight: Theme.rowHeight

    Item {
        id: badge
        anchors.left: parent.left
        anchors.leftMargin: Theme.s3
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.px(28)
        height: width

        Monogram {
            visible: !art.ready
            size: parent.width
            title: root.parsed.title
            system: root.system
        }

        Art {
            id: art
            anchors.fill: parent
            source: root.thumbnail
            radius: Theme.px(6)
            shadow: false
        }
    }

    Label {
        id: title
        anchors.left: badge.right
        anchors.leftMargin: Theme.s3
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, trailing.x - x - Theme.s3 - (subtitle.text !== "" ? Math.min(subtitle.implicitWidth, Theme.px(140)) + Theme.s2 : 0))
        text: root.parsed.title
        font.weight: root.selected ? Font.Medium : Font.Normal
    }

    Label {
        id: subtitle
        anchors.left: title.right
        anchors.leftMargin: Theme.s2
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.min(implicitWidth, trailing.x - x - Theme.s3))
        variant: "label"
        text: root.parsed.tags.join(", ")
        color: Theme.inkFaint
    }

    Row {
        id: trailing
        anchors.right: parent.right
        anchors.rightMargin: Theme.s3
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.s2

        Glyph {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.game ? root.game.favorite : false
            name: "heart"
            size: Theme.px(14)
            color: Theme.red
        }

        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            variant: "label"
            text: root.game && root.game.releaseYear > 0 ? String(root.game.releaseYear) : ""
            color: Theme.inkDim
        }
    }
}
