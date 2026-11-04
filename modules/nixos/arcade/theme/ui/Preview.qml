import QtQuick 2.15
import "."
import "Titles.js" as Titles

// The selected game, large: its box art, or a big monogram until it's been
// scraped, then the title, its tags, what's known about it and the
// description. A raised surface inside the glass, like the shell's tiles.
Rectangle {
    id: root

    property var game: null

    readonly property var parsed: Titles.parse(game ? game.title : "")
    readonly property string system: game && game.collections.count > 0 ? game.collections.get(0).shortName : ""
    readonly property string systemName: game && game.collections.count > 0 ? game.collections.get(0).name : ""
    readonly property string cover: game ? (game.assets.boxFront || game.assets.screenshot || game.assets.titlescreen) : ""
    readonly property string description: game ? (game.description || game.summary) : ""
    readonly property var facts: {
        if (!game)
            return [];
        var out = [];
        if (game.releaseYear > 0)
            out.push(String(game.releaseYear));
        if (game.players > 1)
            out.push("1–" + game.players + " players");
        if (game.genre)
            out.push(game.genre);
        if (game.developer)
            out.push(game.developer);
        return out;
    }

    radius: Theme.rLg
    color: Theme.surfaceBase
    antialiasing: true

    Item {
        id: hero
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.s5
        height: parent.height * 0.5

        Art {
            id: art
            anchors.fill: parent
            source: root.cover
            radius: Theme.rMd
        }

        Monogram {
            anchors.centerIn: parent
            visible: !art.ready
            size: Math.min(parent.width, parent.height) * 0.72
            title: root.parsed.title
            system: root.system
        }
    }

    Column {
        anchors.top: hero.bottom
        anchors.topMargin: Theme.s5
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.s5
        anchors.rightMargin: Theme.s5
        spacing: Theme.s3

        Row {
            width: parent.width
            spacing: Theme.s3

            Label {
                id: title
                width: Math.min(implicitWidth, parent.width - (heart.visible ? heart.width + parent.spacing : 0))
                variant: "header"
                font.pixelSize: Theme.px(26)
                font.letterSpacing: Theme.headerTracking
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                text: root.parsed.title
            }

            Glyph {
                id: heart
                anchors.verticalCenter: title.verticalCenter
                visible: root.game ? root.game.favorite : false
                name: "heart"
                size: Theme.px(20)
                color: Theme.red
                scale: visible ? 1 : 0.4
                Behavior on scale {
                    NumberAnimation { duration: Theme.dSpring; easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
                }
            }
        }

        Flow {
            width: parent.width
            spacing: Theme.s2
            visible: chips.count > 0

            Repeater {
                id: chips
                model: [root.systemName].concat(root.parsed.tags).filter(function (tag) { return tag !== ""; })
                Chip { text: modelData }
            }
        }

        Label {
            width: parent.width
            visible: text !== ""
            variant: "label"
            color: Theme.inkDim
            text: root.facts.join("  ·  ")
        }

        Label {
            width: parent.width
            visible: text !== ""
            text: root.description
            color: Theme.inkDim
            wrapMode: Text.WordWrap
            maximumLineCount: 5
            lineHeight: 1.15
        }

        Label {
            width: parent.width
            visible: root.game !== null && root.description === "" && !art.ready
            variant: "caption"
            color: Theme.inkFaint
            wrapMode: Text.WordWrap
            text: "No art or details yet: arcade-scrape fetches them."
        }
    }
}
