import QtQuick
import Quickshell
import "../../theme"
import "../../config"
import "../../services"
import "../../components"
import "Calculator.js" as Calc

// The launcher's guts: a search bar (top) plus results (below). This is NOT a
// window; it lives INSIDE the bar's island, which morphs to host it (see Bar.qml).
// The island grows around this; we just hand over the content and its natural
// implicitHeight (so the island knows how tall to get). Modes by prefix:
//   (none) → apps · "=" → calculator · ":" → clipboard.
Item {
    id: root

    property bool active: false               // true while the island's wearing its launcher form
    implicitHeight: column.implicitHeight      // this is what tells the island how tall to be
    clip: true

    readonly property int rowH: Config.launcherRowHeight
    readonly property int listCap: rowH * Config.launcherMaxRows

    // ----- mode + query -----
    readonly property string mode: {
        const t = field.text;
        if (t.startsWith("=")) return "calc";
        if (t.startsWith(":")) return "clip";
        return "apps";
    }
    readonly property string queryBody: mode === "apps" ? field.text : field.text.slice(1)
    readonly property string modeLabel: mode === "calc" ? "Calculator"
                                      : mode === "clip" ? "Clipboard" : "Apps"

    readonly property var items: !active ? [] : buildItems()
    property int index: 0

    function buildItems() {
        if (mode === "calc") return calcItems();
        if (mode === "clip") return clipItems();
        return appItems();
    }

    function appItems() {
        // Icon NAME only; we resolve the real path per visible row. Resolving every
        // app's path up front is what made the first open feel sluggish.
        return Apps.query(queryBody).map(e => ({
            iconName: e.icon,
            title: e.name,
            subtitle: e.genericName || e.comment || "",
            run: () => e.execute()
        }));
    }

    function calcItems() {
        const expr = queryBody.trim();
        if (expr === "")
            return [{ icon: "", title: "Type an expression", subtitle: "e.g.  = 2+2 · sqrt(16) · pi*3", run: () => {} }];
        const r = Calc.tryEval(expr);
        if (!r.ok)
            return [{ icon: "", title: "-", subtitle: "invalid expression", run: () => {} }];
        const val = formatNum(r.value);
        return [{ icon: "", title: val, subtitle: `= ${expr}    ·    Enter to copy`, run: () => Clipboard.setText(val) }];
    }

    function clipItems() {
        const q = queryBody.trim().toLowerCase();
        let list = Clipboard.entries;
        if (q !== "")
            list = list.filter(e => e.preview.toLowerCase().indexOf(q) >= 0);
        return list.map(e => ({
            icon: "", title: e.preview, subtitle: "", run: () => Clipboard.copy(e)
        }));
    }

    function formatNum(v) {
        if (Number.isInteger(v)) return String(v);
        return String(parseFloat(v.toFixed(8)));
    }

    function close() { GlobalState.launcherOpen = false; }
    function activate() {
        const it = items[index];
        if (!it) return;
        it.run();
        close();
    }

    onModeChanged: if (mode === "clip") Clipboard.refresh()
    onItemsChanged: { index = 0; syncResults(); }

    // Back the list with a ListModel kept in sync by a key-diff (insert / remove / move) so the
    // ListView's add/remove/displaced transitions animate the rows reflowing as you filter.
    // Just reassigning a JS-array model resets the whole view and skips the animation.
    ListModel { id: resultModel }
    function itKey(it) { return (it.title ?? "") + "" + (it.subtitle ?? ""); }
    function syncResults() {
        const items = root.items;
        const lm = resultModel;
        for (let i = lm.count - 1; i >= 0; i--) {
            const k = lm.get(i).key;
            if (!items.some(it => root.itKey(it) === k)) lm.remove(i);
        }
        for (let i = 0; i < items.length; i++) {
            const it = items[i];
            const k = root.itKey(it);
            let cur = -1;
            for (let j = i; j < lm.count; j++) { if (lm.get(j).key === k) { cur = j; break; } }
            if (cur === -1) lm.insert(i, { key: k, iconName: it.iconName ?? "", title: it.title ?? "", subtitle: it.subtitle ?? "" });
            else if (cur !== i) lm.move(cur, i, 1);
        }
    }
    onActiveChanged: {
        if (active) {
            field.text = "";
            index = 0;
            Clipboard.refresh();
            Qt.callLater(() => field.forceActiveFocus());
        }
    }

    Column {
        id: column
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.s3

        // search bar (TOP), the morphed island itself: magnifier + input
        Item {
            id: searchBar
            width: parent.width
            height: Theme.s6 + Theme.s1

            Icon {
                id: glass
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                color: Theme.inkDim
            }

            TextInput {
                id: field
                anchors.left: glass.right
                anchors.leftMargin: Theme.s3
                anchors.right: chip.visible ? chip.left : parent.right
                anchors.rightMargin: chip.visible ? Theme.s2 : 0
                anchors.verticalCenter: parent.verticalCenter
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Theme.inkPrimary
                selectionColor: Theme.alpha(Theme.hue("launcher"), 0.4)
                font.family: Theme.fontBody
                font.pixelSize: Theme.fsBody

                onAccepted: root.activate()
                Keys.onUpPressed: root.index = Math.max(0, root.index - 1)
                Keys.onDownPressed: root.index = Math.min(root.items.length - 1, root.index + 1)
                Keys.onEscapePressed: root.close()

                StyledText {
                    capCentreIn: parent
                    visible: field.text.length === 0
                    variant: "body"
                    color: Theme.inkFaint
                    text: "Search…"
                }
            }

            // mode chip, only shows outside apps mode
            Rectangle {
                id: chip
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.mode !== "apps"
                implicitWidth: chipLabel.implicitWidth + Theme.s3
                height: chipLabel.implicitHeight + Theme.s2
                radius: Theme.rPill
                color: Theme.fillLow

                StyledText {
                    id: chipLabel
                    anchors.centerIn: parent
                    variant: "caption"
                    text: root.modeLabel
                    color: Theme.hue("launcher")
                    font.weight: Theme.wMedium
                }
            }
        }

        // results group (BELOW), staggers in just after the bar forms
        Column {
            id: resultsGroup
            width: parent.width
            spacing: Theme.s3

            opacity: root.active ? 1 : 0
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: Theme.dur(Theme.stagger) }
                    NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.hairline
            }

            ListView {
                id: list
                width: parent.width
                height: Math.min(contentHeight, root.listCap)
                visible: root.items.length > 0
                clip: true
                model: resultModel
                currentIndex: root.index
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                // filter animations: new rows fade in, dead rows fade out, the rest glide
                add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                remove: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                displaced: Transition { NumberAnimation { properties: "x,y"; duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                move: Transition { NumberAnimation { properties: "x,y"; duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }

                delegate: ListRow {
                    id: row
                    required property string key
                    required property string iconName
                    required property string title
                    required property string subtitle
                    required property int index

                    width: ListView.view.width
                    implicitHeight: root.rowH
                    baseColor: Theme.base     // opaque BLACK (matches the island), not the wallpaper-tinted bg, so reflowing rows cover each other (no text bleed during the filter anims)
                    selected: index === root.index
                    onClicked: { root.index = index; root.activate(); }
                    onEntered: root.index = index

                    readonly property string iconSrc: row.iconName !== ""
                        ? Quickshell.iconPath(row.iconName, "application-x-executable")
                        : ""

                    // icon badge: rounded square in a flat tint (mode glyph for calc/clip)
                    Rectangle {
                        id: badge
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        height: 36
                        radius: Theme.rSm
                        color: Theme.fillLow

                        Image {
                            id: ic
                            anchors.centerIn: parent
                            source: row.iconSrc
                            visible: source != ""
                            width: 24
                            height: 24
                            sourceSize.width: 24
                            sourceSize.height: 24
                            asynchronous: true
                            cache: true
                        }
                        Icon {
                            anchors.centerIn: parent
                            visible: !ic.visible
                            name: root.mode === "calc" ? "calculator" : root.mode === "clip" ? "clipboard" : "apps"
                            color: Theme.hue("launcher")
                        }
                    }

                    Column {
                        anchors.left: badge.right
                        anchors.leftMargin: Theme.s3
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        StyledText {
                            width: parent.width
                            variant: "body"
                            font.weight: Theme.wMedium
                            text: row.title
                            color: Theme.inkPrimary
                            elide: Text.ElideRight
                        }
                        StyledText {
                            width: parent.width
                            variant: "caption"
                            visible: row.subtitle !== ""
                            text: row.subtitle
                            color: Theme.inkDim
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // empty state. Only while active: items empties the instant the launcher is
            // dismissed, and this was flashing "No results" over the fade-out.
            StyledText {
                width: parent.width
                visible: root.active && root.items.length === 0
                horizontalAlignment: Text.AlignHCenter
                topPadding: Theme.s2
                bottomPadding: Theme.s2
                variant: "body"
                color: Theme.inkFaint
                text: root.mode === "clip" ? "Clipboard empty" : "No results"
            }
        }
    }
}
