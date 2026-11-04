import QtQuick 2.15
import QtGraphicalEffects 1.12
import SortFilterProxyModel 0.2
import "ui"
import "ui/Titles.js" as Titles

// The station's game menu, drawn the way the desktop shell draws its launcher:
// one glass card hanging in the middle of the screen, systems as capsules
// across its top, games as rows on the left, the selected one large on the
// right, and the buttons that do things along the bottom. The look is
// modules/theme's, shared with the shell; ui/ holds the pieces.
//
// Pegasus tears the theme down to launch a game and builds it again after, so
// where the cursor was is kept in api.memory and put back on load.
FocusScope {
    id: root

    focus: true

    Binding { target: Theme; property: "screenWidth"; value: root.width }
    Binding { target: Theme; property: "screenHeight"; value: root.height }

    SortFilterProxyModel {
        id: favorites
        sourceModel: api.allGames
        filters: ValueFilter { roleName: "favorite"; value: true }
    }

    SortFilterProxyModel {
        id: recent
        sourceModel: api.allGames
        filters: RangeFilter { roleName: "playCount"; minimumValue: 1 }
        sorters: RoleSorter { roleName: "lastPlayed"; sortOrder: Qt.DescendingOrder }
    }

    // [{ key, label, name, model, proxy }]
    property var tabs: []
    property int tabIndex: 0
    readonly property var tab: tabs.length > 0 ? tabs[Math.min(tabIndex, tabs.length - 1)] : null
    readonly property var game: tab && list.count > 0 ? gameAt(list.currentIndex) : null

    // Each tab's cursor, so going back to a system lands where it was left.
    property var positions: ({})

    readonly property bool hasFavorites: favorites.count > 0
    readonly property bool hasRecent: recent.count > 0
    onHasFavoritesChanged: buildTabs(tab ? tab.key : "")
    onHasRecentChanged: buildTabs(tab ? tab.key : "")

    function buildTabs(keep) {
        var built = [];
        if (hasRecent)
            built.push({ key: "recent", label: "Recent", name: "Recently played", model: recent, proxy: true });
        if (hasFavorites)
            built.push({ key: "favorites", label: "Favorites", name: "Favorites", model: favorites, proxy: true });
        for (var i = 0; i < api.collections.count; i++) {
            var collection = api.collections.get(i);
            built.push({
                key: "system:" + collection.shortName,
                label: Theme.labels[collection.shortName] || collection.name,
                name: collection.name,
                model: collection.games,
                proxy: false
            });
        }

        var index = 0;
        for (var j = 0; j < built.length; j++) {
            if (built[j].key === keep)
                index = j;
        }
        tabs = built;
        tabIndex = index;
    }

    function gameAt(index) {
        if (!tab || index < 0 || index >= tab.model.count)
            return null;
        return tab.proxy ? api.allGames.get(tab.model.mapToSource(index)) : tab.model.get(index);
    }

    function titleAt(index) {
        var found = gameAt(index);
        return found ? found.title : "";
    }

    function remember() {
        if (tab)
            positions[tab.key] = list.currentIndex;
    }

    function persist() {
        remember();
        if (tab)
            api.memory.set("tab", tab.key);
        api.memory.set("positions", positions);
    }

    function restore() {
        var key = tab ? tab.key : "";
        var index = positions[key] || 0;
        list.currentIndex = Math.max(0, Math.min(index, list.count - 1));
        list.positionViewAtIndex(list.currentIndex, ListView.Center);
    }

    function switchTab(step) {
        if (tabs.length < 2)
            return;
        remember();
        tabIndex = (tabIndex + step + tabs.length) % tabs.length;
        restore();
        swap.step = step;
        swap.restart();
    }

    // L2 and R2: to the first game under the next letter, or back to the
    // start of this one and then the one before.
    function jump(step) {
        var count = list.count;
        if (count === 0)
            return;
        var index = list.currentIndex;
        var letter = Titles.letter(titleAt(index));
        if (step > 0) {
            var next = index + 1;
            while (next < count && Titles.letter(titleAt(next)) === letter)
                next++;
            if (next >= count)
                return;
            index = next;
        } else {
            var start = index;
            while (start > 0 && Titles.letter(titleAt(start - 1)) === letter)
                start--;
            if (start === index && index > 0) {
                var previous = Titles.letter(titleAt(index - 1));
                start = index - 1;
                while (start > 0 && Titles.letter(titleAt(start - 1)) === previous)
                    start--;
            }
            index = start;
        }
        list.currentIndex = index;
        hud.show(Titles.letter(titleAt(index)));
    }

    function launch() {
        if (!game)
            return;
        persist();
        game.launch();
    }

    Component.onCompleted: {
        var saved = api.memory.get("positions");
        positions = saved ? saved : {};
        buildTabs(api.memory.get("tab") || "");
        restore();
        entrance.start();
    }

    Component.onDestruction: persist()

    Keys.onPressed: {
        if (event.isAutoRepeat && (api.keys.isAccept(event) || api.keys.isFilters(event)))
            return;

        if (api.keys.isUp(event)) {
            event.accepted = true;
            list.decrementCurrentIndex();
        } else if (api.keys.isDown(event)) {
            event.accepted = true;
            list.incrementCurrentIndex();
        } else if (api.keys.isLeft(event) || api.keys.isPrevPage(event)) {
            event.accepted = true;
            switchTab(-1);
        } else if (api.keys.isRight(event) || api.keys.isNextPage(event)) {
            event.accepted = true;
            switchTab(1);
        } else if (api.keys.isPageUp(event)) {
            event.accepted = true;
            jump(-1);
        } else if (api.keys.isPageDown(event)) {
            event.accepted = true;
            jump(1);
        } else if (api.keys.isAccept(event)) {
            event.accepted = true;
            launch();
        } else if (api.keys.isFilters(event)) {
            event.accepted = true;
            if (game)
                game.favorite = !game.favorite;
        }
    }

    // The backdrop follows the selected game's art once the cursor rests.
    property string art: ""
    onGameChanged: artDelay.restart()
    Timer {
        id: artDelay
        interval: Theme.station.artDelay
        onTriggered: {
            var assets = root.game ? root.game.assets : null;
            root.art = assets ? (assets.screenshot || assets.background || assets.titlescreen || "") : "";
        }
    }

    Backdrop {
        id: backdrop
        anchors.fill: parent
        art: root.art
    }

    Item {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 2 * Theme.px(56)
        height: parent.height - 2 * Theme.px(40)

        // The shell's island drops in the same way.
        opacity: 0
        transform: Translate { id: drop; y: -Theme.px(22) }
        ParallelAnimation {
            id: entrance
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: Theme.dEnter; easing.type: Easing.OutCubic }
            NumberAnimation { target: drop; property: "y"; from: -Theme.px(22); to: 0; duration: Theme.dEnter; easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
        }

        Pane {
            anchors.fill: parent
            radius: Theme.rIslandOpen
            backdrop: backdrop.blurred
        }

        Item {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.panelPad
            height: Theme.px(44)

            Tabs {
                anchors.left: parent.left
                anchors.right: clock.left
                anchors.rightMargin: Theme.s5
                anchors.verticalCenter: parent.verticalCenter
                tabs: root.tabs
                current: root.tabIndex
            }

            Label {
                id: clock
                anchors.right: parent.right
                anchors.rightMargin: Theme.s2
                anchors.verticalCenter: parent.verticalCenter
                variant: "header"
                color: Theme.inkSecondary
                text: Qt.formatTime(now, "h:mm AP")
                property date now: new Date()
                Timer {
                    interval: 1000
                    running: true
                    repeat: true
                    onTriggered: clock.now = new Date()
                }
            }
        }

        Rectangle {
            id: topRule
            anchors.top: header.bottom
            anchors.topMargin: Theme.panelPad
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.hairlineWidth
            color: Theme.hairline
        }

        Item {
            id: body
            anchors.top: topRule.bottom
            anchors.bottom: bottomRule.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.panelPad

            LinearGradient {
                id: listFade
                visible: false
                width: listArea.width
                height: listArea.height
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: Theme.s4 / Math.max(1, listFade.height); color: "white" }
                    GradientStop { position: 1 - Theme.s6 / Math.max(1, listFade.height); color: "white" }
                    GradientStop { position: 1; color: "transparent" }
                }
            }

            Item {
                id: listArea
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * 0.56

                transform: Translate { id: listShift }

                // Rows fade out at the list's ends rather than being cut off
                // by its edge. Safe as a layer: nothing in here is a Pane.
                layer.enabled: true
                layer.effect: OpacityMask { maskSource: listFade }

                ListView {
                    id: list
                    anchors.fill: parent
                    clip: true
                    model: root.tab ? root.tab.model : null
                    interactive: false
                    keyNavigationEnabled: false
                    spacing: Theme.px(2)
                    cacheBuffer: Theme.rowHeight * 10

                    highlightMoveDuration: Theme.dBase
                    highlightMoveVelocity: -1
                    highlightResizeDuration: 0
                    highlightRangeMode: ListView.ApplyRange
                    preferredHighlightBegin: height * 0.3
                    preferredHighlightEnd: height * 0.7
                    highlight: Rectangle {
                        radius: Theme.rRow
                        color: Theme.selection
                        antialiasing: true
                    }

                    delegate: GameRow {
                        width: ListView.view.width
                        game: modelData
                        selected: ListView.isCurrentItem
                    }
                }

                Label {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    color: Theme.inkDim
                    text: root.tabs.length === 0 ? "No games yet" : "Nothing here"
                }
            }

            Preview {
                anchors.left: listArea.right
                anchors.leftMargin: Theme.panelPad
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                game: root.game
                visible: root.game !== null
            }

            Column {
                anchors.centerIn: parent
                visible: root.tabs.length === 0
                spacing: Theme.s3

                Glyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "controller"
                    size: Theme.px(48)
                    color: Theme.inkDim
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    variant: "title"
                    text: "No games yet"
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.inkDim
                    text: "Copy them into /srv/arcade/roms/<system>"
                }
            }
        }

        Rectangle {
            id: bottomRule
            anchors.bottom: footer.top
            anchors.bottomMargin: Theme.panelPad
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.hairlineWidth
            color: Theme.hairline
        }

        Item {
            id: footer
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.panelPad
            height: Theme.px(28)

            Label {
                anchors.left: parent.left
                anchors.leftMargin: Theme.s3
                anchors.verticalCenter: parent.verticalCenter
                variant: "label"
                color: Theme.inkDim
                text: root.tab ? root.tab.name + "  ·  " + list.count + (list.count === 1 ? " game" : " games") : ""
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: Theme.s2
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.s5

                Hint { text: "Play"; keys: [{ glyph: "cross" }] }
                Hint { text: root.game && root.game.favorite ? "Unfavorite" : "Favorite"; keys: [{ glyph: "triangle" }] }
                Hint { text: "System"; keys: [{ text: "L1" }, { text: "R1" }] }
                Hint { text: "Letter"; keys: [{ text: "L2" }, { text: "R2" }] }
            }
        }

        // The letter L2 or R2 landed on, the way the shell's HUD shows a
        // change: a glass capsule that fades in over the list and out again.
        Item {
            id: hud

            property string letter: ""
            function show(value) {
                letter = value;
                hudFade.restart();
            }

            x: body.x + listArea.width / 2 - width / 2
            y: body.y + body.height / 2 - height / 2
            width: Theme.px(112)
            height: width
            opacity: 0
            scale: 0.92 + 0.08 * opacity

            Pane {
                anchors.fill: parent
                radius: Theme.rXl
                tint: Theme.glassStrong
                backdrop: backdrop.blurred
            }

            Label {
                anchors.centerIn: parent
                variant: "display"
                font.pixelSize: Theme.px(56)
                text: hud.letter
            }

            SequentialAnimation {
                id: hudFade
                NumberAnimation { target: hud; property: "opacity"; to: 1; duration: Theme.dFast; easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
                PauseAnimation { duration: 600 }
                NumberAnimation { target: hud; property: "opacity"; to: 0; duration: Theme.dEffects; easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
            }
        }
    }

    // A new system's list slides in from the side it was reached from.
    SequentialAnimation {
        id: swap
        property int step: 1
        ScriptAction {
            script: {
                list.opacity = 0;
                listShift.x = swap.step * Theme.px(28);
            }
        }
        ParallelAnimation {
            NumberAnimation { target: list; property: "opacity"; to: 1; duration: Theme.dEffects; easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
            NumberAnimation { target: listShift; property: "x"; to: 0; duration: Theme.dSpring; easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
        }
    }
}
