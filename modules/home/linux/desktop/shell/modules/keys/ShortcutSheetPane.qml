import QtQuick
import QtQuick.Effects
import "../../theme"
import "../../services"
import "../../components"

// The shortcut sheet's glass pane: a search field over every described bind, grouped into
// columns, each row the action on the left and its keys on the right. Typing filters the
// rows live. ShortcutSheet places it on screen.
Rectangle {
    id: pane

    property bool active: false
    property int columns: 3
    // the tallest the pane may get before its body scrolls
    property real maxHeight: 900

    readonly property int padH: Theme.s5
    readonly property int padV: Theme.s3
    readonly property int columnWidth: 360
    readonly property int gutter: Theme.s6
    readonly property int rowH: 28
    readonly property int groupHeaderH: 30
    readonly property int groupGap: Theme.s5

    readonly property var terms: field.text.toLowerCase().split(/\s+/).filter(t => t !== "")
    readonly property var filteredGroups: Keybinds.groups
        .map(g => ({ title: g.title, rows: g.rows.filter(r => terms.every(t => r.search.indexOf(t) >= 0)) }))
        .filter(g => g.rows.length > 0)
    readonly property var packed: pack(filteredGroups)
    // Sized for every bind, so the pane holds still while a search empties it.
    readonly property real fullBodyHeight: tallest(pack(Keybinds.groups))

    function groupHeight(group) { return groupHeaderH + group.rows.length * rowH; }
    function columnHeight(column) {
        return column.reduce((sum, g, i) => sum + groupHeight(g) + (i > 0 ? groupGap : 0), 0);
    }
    function tallest(packing) { return packing.reduce((most, column) => Math.max(most, columnHeight(column)), 0); }

    // Deal the groups into columns so the tallest column is as short as it can be. Keeping
    // them strictly in order stacked Shell on Windows and scrolled, so any group may go in
    // any column; among equally short packings the one keeping the most neighbours together
    // wins, and each column keeps the groups' own order. A handful of groups makes trying
    // every assignment cheap, and past nine the plain in-order split stands in.
    function pack(groups) {
        const n = groups.length;
        if (n === 0) return [];
        if (n > 9) return contiguous(groups);
        const assignment = new Array(n).fill(0);
        let best = null;
        const visit = (i, used) => {
            if (i === n) {
                const cols = [];
                for (let g = 0; g < n; g++) (cols[assignment[g]] = cols[assignment[g]] || []).push(groups[g]);
                let together = 0;
                for (let g = 1; g < n; g++) if (assignment[g] === assignment[g - 1]) together++;
                const score = tallest(cols) * 1000 - together;
                if (best === null || score < best.score) best = { score, cols };
                return;
            }
            // a new column only ever opens as the next one, so no packing is tried twice
            for (let c = 0; c <= Math.min(used, columns - 1); c++) {
                assignment[i] = c;
                visit(i + 1, Math.max(used, c + 1));
            }
        };
        visit(0, 0);
        return best.cols;
    }
    function contiguous(groups) {
        const perColumn = Math.ceil(groups.length / columns);
        const out = [];
        for (let i = 0; i < groups.length; i += perColumn) out.push(groups.slice(i, i + perColumn));
        return out;
    }

    onActiveChanged: {
        if (!active) return;
        field.text = "";
        body.contentY = 0;
        Qt.callLater(() => field.forceActiveFocus());
    }

    width: columns * columnWidth + (columns - 1) * gutter + padH * 2
    height: Math.min(maxHeight, header.height + 1 + Theme.s4 + Math.max(fullBodyHeight, emptyState.height) + Theme.s5)
    radius: Theme.rIslandOpen
    color: Theme.base
    border.width: 1
    border.color: Theme.rim

    layer.enabled: Theme.shadows
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Theme.shadow
        shadowBlur: Theme.shadowBlur
        shadowVerticalOffset: Theme.shadowY
        blurMax: Theme.shadowBlurMax
        autoPaddingEnabled: true
    }

    // keeps a click on the pane from reaching the backdrop behind it, which closes the sheet
    MouseArea { anchors.fill: parent }

    Item {
        id: header
        x: Theme.s2 + 2
        width: parent.width - x * 2
        height: 56

        Icon {
            id: glass
            anchors.left: parent.left
            anchors.leftMargin: Theme.s3 + 2
            anchors.verticalCenter: parent.verticalCenter
            name: "search"
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

            // Escape clears a search first and only closes from an empty field, as in the launcher
            Keys.onEscapePressed: { if (field.text !== "") field.text = ""; else Keybinds.closeSheet(); }
            Keys.onUpPressed: body.flick(0, 800)
            Keys.onDownPressed: body.flick(0, -800)

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: field.text.length === 0
                font: field.font
                color: Theme.inkFaint
                elide: Text.ElideRight
                text: "Search keyboard shortcuts…"
            }
        }

        Row {
            id: hints
            anchors.right: parent.right
            anchors.rightMargin: Theme.s3
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.s2
            StyledText { anchors.verticalCenter: parent.verticalCenter; variant: "label"; color: Theme.inkDim; text: "Close" }
            Keycap { anchors.verticalCenter: parent.verticalCenter; text: "esc" }
        }
    }

    Rectangle {
        id: divider
        anchors.top: header.bottom
        width: parent.width
        height: 1
        color: Theme.hairline
    }

    Flickable {
        id: body
        anchors.top: divider.bottom
        anchors.topMargin: Theme.s4
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.s5
        x: pane.padH
        width: parent.width - pane.padH * 2
        clip: true
        contentWidth: width
        contentHeight: columnsRow.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Row {
            id: columnsRow
            spacing: pane.gutter

            Repeater {
                model: pane.packed
                delegate: Column {
                    id: column
                    required property var modelData
                    width: pane.columnWidth
                    spacing: pane.groupGap

                    Repeater {
                        model: column.modelData
                        delegate: Column {
                            id: group
                            required property var modelData
                            width: pane.columnWidth

                            Item {
                                width: parent.width
                                height: pane.groupHeaderH
                                StyledText {
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 8
                                    variant: "caption"
                                    font.weight: Theme.wMedium
                                    color: Theme.inkDim
                                    text: group.modelData.title
                                }
                            }

                            Repeater {
                                model: group.modelData.rows
                                delegate: Item {
                                    id: row
                                    required property var modelData
                                    width: pane.columnWidth
                                    height: pane.rowH

                                    KeyCombo {
                                        id: combo
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        alts: row.modelData.alts
                                    }
                                    StyledText {
                                        anchors.left: parent.left
                                        anchors.right: combo.left
                                        anchors.rightMargin: Theme.s3
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        text: row.modelData.label
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    StyledText {
        id: emptyState
        anchors.top: divider.bottom
        anchors.topMargin: Theme.s4
        width: parent.width
        height: pane.rowH * 3
        visible: pane.filteredGroups.length === 0
        horizontalAlignment: Text.AlignHCenter
        color: Theme.inkFaint
        text: Keybinds.rows.length === 0 ? "No described keybindings" : "No shortcuts match"
    }
}
