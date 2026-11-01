import QtQuick
import Quickshell
import "../../theme"
import "../../config"
import "../../services"
import "../../components"
import "Calculator.js" as Calc

// The launcher, laid out after Raycast: a large search field, a section label, result
// rows (icon, title, a dim subtitle inline, a type label on the right), and a footer with
// the primary action and its keys. It is not a window: the bar's island morphs to host it
// and reads implicitHeight to know how tall to get (see Bar.qml). Modes by prefix:
//   (none) → apps · "=" → calculator · ":" → clipboard history.
Item {
    id: root

    property bool active: false
    implicitHeight: column.implicitHeight
    clip: true

    readonly property int rowH: Config.launcherRowHeight
    readonly property int rowGap: 2
    readonly property int listCap: (rowH + rowGap) * Config.launcherMaxRows - rowGap
    // inner inset shared by the header, the section label, the rows and the footer, so
    // the search glyph, the label and the row icons all sit on one vertical line
    readonly property int inset: Theme.s3

    readonly property string mode: {
        const t = field.text;
        if (t.startsWith("=")) return "calc";
        if (t.startsWith(":")) return "clip";
        return "apps";
    }
    readonly property string queryBody: mode === "apps" ? field.text : field.text.slice(1)

    readonly property var items: !active ? [] : buildItems()
    property int index: 0
    readonly property var current: items[index] ?? null

    function buildItems() {
        if (mode === "calc") return calcItems();
        if (mode === "clip") return clipItems();
        return appItems();
    }

    function appItems() {
        // Icon NAME only; the path is resolved per visible row, which keeps the first open
        // quick. Subtitle is the generic name ("Web Browser") unless it just repeats the name.
        return Apps.query(queryBody).map(e => {
            const gen = e.genericName && e.genericName !== e.name ? e.genericName : "";
            return {
                iconName: e.icon,
                glyph: "apps",
                title: e.name,
                subtitle: gen,
                kind: "Application",
                action: "Open Application",
                run: () => root.launch(e)
            };
        });
    }

    function calcItems() {
        const expr = queryBody.trim();
        if (expr === "")
            return [{ glyph: "calculator", title: "Type an expression", subtitle: "2+2, sqrt(16), pi*3", kind: "Calculator", action: "", run: null }];
        const r = Calc.tryEval(expr);
        if (!r.ok)
            return [{ glyph: "calculator", title: "Not an expression yet", subtitle: expr, kind: "Calculator", action: "", run: null }];
        const val = formatNum(r.value);
        return [{
            glyph: "calculator", title: val, subtitle: `= ${expr}`, kind: "Calculator",
            action: "Copy Answer",
            run: () => { Clipboard.setText(val); OsdState.showHud("Copied to clipboard", "calculator"); }
        }];
    }

    function clipItems() {
        const q = queryBody.trim().toLowerCase();
        let list = Clipboard.entries;
        if (q !== "")
            list = list.filter(e => e.preview.toLowerCase().indexOf(q) >= 0);
        return list.map(e => {
            // cliphist previews binary entries as "[[ binary data 1.2 MiB png 1920x1080 ]]"
            const image = e.preview.startsWith("[[ binary data");
            return {
                glyph: "clipboard",
                title: e.preview,
                subtitle: "",
                kind: image ? "Image" : "Text",
                action: "Copy to Clipboard",
                run: () => { Clipboard.copy(e); OsdState.showHud("Copied to clipboard", "clipboard"); }
            };
        });
    }

    function formatNum(v) {
        if (Number.isInteger(v)) return String(v);
        return String(parseFloat(v.toFixed(8)));
    }

    // Launch through uwsm so the app gets its own systemd scope instead of living (and
    // dying) in the shell's cgroup. The desktop file ID is the entry's id plus the suffix;
    // an entry without one (rare: it came from somewhere other than a data dir) falls back
    // to Quickshell's own exec of its Exec line.
    function launch(e) {
        if (e.id && e.id !== "")
            Quickshell.execDetached(["uwsm", "app", "--", e.id + ".desktop"]);
        else
            e.execute();
    }

    function close() { GlobalState.launcherOpen = false; }
    function activate() {
        const it = items[index];
        if (!it || !it.run) return;
        it.run();
        close();
    }
    function move(delta) {
        if (items.length === 0) return;
        index = Math.max(0, Math.min(items.length - 1, index + delta));
    }
    // Tab walks the list and wraps, the way a picker cycles
    function cycle(delta) {
        if (items.length === 0) return;
        index = (index + delta + items.length) % items.length;
    }

    onModeChanged: if (mode === "clip") Clipboard.refresh()
    onItemsChanged: { index = 0; syncResults(); }

    // Back the list with a ListModel kept in sync by a key-diff (insert / remove / move) so the
    // ListView's add/remove/displaced transitions animate the rows reflowing as you filter.
    // Reassigning a JS-array model resets the whole view and skips the animation.
    ListModel { id: resultModel }
    function itKey(it) { return (it.title ?? "") + "\u0001" + (it.subtitle ?? "") + "\u0001" + (it.kind ?? ""); }
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
            if (cur === -1)
                lm.insert(i, { key: k, iconName: it.iconName ?? "", glyph: it.glyph ?? "apps",
                               title: it.title ?? "", subtitle: it.subtitle ?? "", kind: it.kind ?? "" });
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
        spacing: 0

        // ── search field ──
        Item {
            id: header
            width: parent.width
            height: 56

            Icon {
                id: glass
                anchors.left: parent.left
                anchors.leftMargin: root.inset + 2
                anchors.verticalCenter: parent.verticalCenter
                name: root.mode === "calc" ? "calculator" : root.mode === "clip" ? "clipboard" : "search"
                size: 22
                color: Theme.inkDim
            }

            TextInput {
                id: field
                anchors.left: glass.right
                anchors.leftMargin: Theme.s3 + 2
                anchors.right: hints.left
                anchors.rightMargin: Theme.s3
                anchors.verticalCenter: parent.verticalCenter
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Theme.inkPrimary
                selectionColor: Theme.alpha(Theme.accent, 0.35)
                selectedTextColor: Theme.inkPrimary
                font.family: Theme.fontBody
                font.pixelSize: Math.round(Theme.fontSize * 1.45)

                onAccepted: root.activate()
                Keys.onUpPressed: root.move(-1)
                Keys.onDownPressed: root.move(1)
                Keys.onTabPressed: event => { root.cycle(1); event.accepted = true; }
                Keys.onBacktabPressed: event => { root.cycle(-1); event.accepted = true; }
                // Escape clears a query first and only closes from an empty field, so backing
                // out of a mode doesn't throw the whole launcher away
                Keys.onEscapePressed: { if (field.text !== "") field.text = ""; else root.close(); }
                Keys.onPressed: event => {
                    const page = Math.max(1, Config.launcherMaxRows - 1);
                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                    if (event.key === Qt.Key_PageDown) { root.move(page); event.accepted = true; }
                    else if (event.key === Qt.Key_PageUp) { root.move(-page); event.accepted = true; }
                    else if (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_J)) { root.move(1); event.accepted = true; }
                    else if (ctrl && (event.key === Qt.Key_P || event.key === Qt.Key_K)) { root.move(-1); event.accepted = true; }
                }

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: field.text.length === 0
                    font: field.font
                    color: Theme.inkFaint
                    elide: Text.ElideRight
                    text: "Search for apps and commands…"
                }
                Text {
                    // the mode's own prompt, shown right after the bare prefix
                    x: field.contentWidth + Theme.s2
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.mode !== "apps" && root.queryBody.length === 0
                    font: field.font
                    color: Theme.inkFaint
                    text: root.mode === "calc" ? "Calculate…" : "Search clipboard history…"
                }
            }

            // Right of the field: with nothing typed, the two prefixes as keys so they can be
            // found at all; inside a mode, which one it is.
            Row {
                id: hints
                anchors.right: parent.right
                anchors.rightMargin: root.inset
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.s2

                component Hint: Row {
                    property string key
                    property string label
                    spacing: Theme.s2
                    StyledText { anchors.verticalCenter: parent.verticalCenter; variant: "label"; color: Theme.inkDim; text: parent.label }
                    Keycap { anchors.verticalCenter: parent.verticalCenter; text: parent.key }
                }

                Hint { visible: field.text.length === 0; label: "Calculator"; key: "=" }
                Item { visible: field.text.length === 0; width: Theme.s2; height: 1 }
                Hint { visible: field.text.length === 0; label: "Clipboard"; key: ":" }
                Hint { visible: root.mode !== "apps"; label: root.mode === "calc" ? "Calculator" : "Clipboard"; key: "esc" }
            }
        }

        // ── section label ──
        Item {
            width: parent.width
            height: 30
            opacity: resultsGroup.opacity
            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: root.inset
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                variant: "caption"
                font.weight: Theme.wMedium
                color: Theme.inkDim
                text: root.mode === "calc" ? "Calculator"
                    : root.mode === "clip" ? "Clipboard History"
                    : root.queryBody.trim() === "" ? "Applications" : "Results"
            }
        }

        // ── results ── staggered in just after the island takes the launcher's shape
        Item {
            id: resultsGroup
            width: parent.width
            height: root.items.length > 0 ? list.height : emptyState.height

            opacity: root.active ? 1 : 0
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: Theme.dur(Theme.stagger) }
                    NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
                }
            }

            ListView {
                id: list
                width: parent.width
                height: Math.min(contentHeight, root.listCap)
                visible: root.items.length > 0
                clip: true
                spacing: root.rowGap
                model: resultModel
                currentIndex: root.index
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                highlightMoveDuration: 0
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                remove: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.dur(Theme.dFast); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                displaced: Transition { NumberAnimation { properties: "x,y"; duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                move: Transition { NumberAnimation { properties: "x,y"; duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }

                delegate: ListRow {
                    id: row
                    required property string key
                    required property string iconName
                    required property string glyph
                    required property string title
                    required property string subtitle
                    required property string kind
                    required property int index

                    width: ListView.view.width
                    implicitHeight: root.rowH
                    selected: index === root.index
                    onClicked: { root.index = index; root.activate(); }
                    onEntered: root.index = index

                    readonly property string iconSrc: row.iconName !== ""
                        ? Quickshell.iconPath(row.iconName, "application-x-executable")
                        : ""

                    Item {
                        id: badge
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 28

                        Image {
                            id: ic
                            anchors.fill: parent
                            source: row.iconSrc
                            visible: source != "" && status !== Image.Error
                            sourceSize.width: 56
                            sourceSize.height: 56
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            asynchronous: true
                            cache: true
                        }
                        // drawn glyph on a soft tile for the rows that have no app icon
                        Rectangle {
                            anchors.fill: parent
                            visible: !ic.visible
                            radius: 8
                            color: Theme.alpha(Theme.accent, 0.16)
                            Icon {
                                anchors.centerIn: parent
                                name: row.glyph
                                size: 17
                                color: Theme.accent
                            }
                        }
                    }

                    StyledText {
                        id: kindLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "label"
                        color: Theme.inkDim
                        text: row.kind
                    }

                    // title then subtitle on one line; the subtitle gives way first
                    Row {
                        anchors.left: badge.right
                        anchors.leftMargin: Theme.s3 + 2
                        anchors.right: kindLabel.left
                        anchors.rightMargin: Theme.s4
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.s3

                        StyledText {
                            id: titleText
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, parent.width)
                            font.pixelSize: Theme.fsBody + 1
                            text: row.title
                            color: Theme.inkPrimary
                            elide: Text.ElideRight
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, Math.min(implicitWidth, parent.width - titleText.width - parent.spacing))
                            visible: row.subtitle !== "" && width > 24
                            font.pixelSize: Theme.fsBody + 1
                            text: row.subtitle
                            color: Theme.inkDim
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // Only while active: items empties the instant the launcher is dismissed, and
            // this would otherwise flash over the fade-out.
            StyledText {
                id: emptyState
                width: parent.width
                height: root.rowH * 2
                visible: root.active && root.items.length === 0
                horizontalAlignment: Text.AlignHCenter
                variant: "body"
                color: Theme.inkFaint
                text: root.mode === "clip" ? "Clipboard history is empty" : "No results"
            }
        }

        Item { width: 1; height: Theme.s2 }

        // ── footer ── the count on the left, the primary action and its keys on the right
        Item {
            id: footer
            width: parent.width
            height: 40
            opacity: resultsGroup.opacity

            Row {
                anchors.left: parent.left
                anchors.leftMargin: root.inset
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.s2
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.mode === "calc" ? "calculator" : root.mode === "clip" ? "clipboard" : "apps"
                    size: 15
                    color: Theme.inkFaint
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    variant: "label"
                    color: Theme.inkDim
                    text: root.mode === "calc" ? "Calculator"
                        : root.items.length === 1 ? "1 result" : `${root.items.length} results`
                }
            }

            // a darker capsule, concentric with the island's corner
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                width: actions.implicitWidth + Theme.s4 * 2
                radius: height / 2
                color: Theme.sunken
                border.width: 1
                border.color: Theme.rim

                Row {
                    id: actions
                    anchors.centerIn: parent
                    spacing: Theme.s2

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: (root.current?.action ?? "") !== ""
                        variant: "label"
                        font.weight: Theme.wMedium
                        color: Theme.inkPrimary
                        text: root.current?.action ?? ""
                    }
                    Keycap { anchors.verticalCenter: parent.verticalCenter; visible: (root.current?.action ?? "") !== ""; text: "↵" }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: (root.current?.action ?? "") !== ""
                        width: 1; height: 16
                        color: Theme.hairline
                    }
                    Item { visible: (root.current?.action ?? "") !== ""; width: 2; height: 1 }
                    StyledText { anchors.verticalCenter: parent.verticalCenter; variant: "label"; color: Theme.inkDim; text: "Navigate" }
                    Keycap { anchors.verticalCenter: parent.verticalCenter; text: "↑" }
                    Keycap { anchors.verticalCenter: parent.verticalCenter; text: "↓" }
                }
            }
        }
    }
}
