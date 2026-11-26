import QtQuick
import "../../theme"
import "../../services"
import "../../components"
import "LayoutRegion.js" as LayoutRegion

// The submap cheat sheet's glass pane, after Moom's: keys right-aligned in one column, a
// thumbnail of where the window goes, then the action. Sections (a "Section · " prefix on
// the descriptions) are split by a gap rather than a heading. SubmapOverlay places it.
Rectangle {
    id: card

    property string submapName: ""
    readonly property var sections: Keybinds.sections(submapName)
    readonly property bool anyGlyph: sections.some(s => s.rows.some(r => LayoutRegion.region(r.label) !== null))

    readonly property int padH: Theme.s5
    readonly property int padV: Theme.s4
    readonly property int rowH: 28

    // the widest key combination, so every row's keys end on the same edge
    readonly property real keyColumnWidth: {
        let widest = 0;
        for (let i = 0; i < sectionRepeater.count; i++) {
            const section = sectionRepeater.itemAt(i);
            if (section) widest = Math.max(widest, section.keysWidth);
        }
        return widest;
    }

    width: Math.max(header.implicitWidth, body.implicitWidth) + padH * 2
    height: padV + header.height + Theme.s3 + body.implicitHeight + padV
    radius: Theme.rIslandOpen
    color: Theme.base
    border.width: 1
    border.color: Theme.rim

    Item {
        id: header
        x: card.padH
        y: card.padV
        width: card.width - card.padH * 2
        height: 28
        implicitWidth: titleText.implicitWidth + Theme.s6 + hint.implicitWidth

        StyledText {
            id: titleText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            variant: "header"
            text: Keybinds.title(card.submapName)
        }
        Row {
            id: hint
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.s2
            Keycap { anchors.verticalCenter: parent.verticalCenter; text: "Esc" }
            StyledText { anchors.verticalCenter: parent.verticalCenter; variant: "label"; color: Theme.inkDim; text: "to exit" }
        }
    }

    Column {
        id: body
        x: card.padH
        y: header.y + header.height + Theme.s3
        spacing: Theme.s4

        Repeater {
            id: sectionRepeater
            model: card.sections
            delegate: Column {
                id: section
                required property var modelData
                spacing: 2

                readonly property real keysWidth: {
                    let widest = 0;
                    for (let i = 0; i < rowRepeater.count; i++) {
                        const row = rowRepeater.itemAt(i);
                        if (row) widest = Math.max(widest, row.keysWidth);
                    }
                    return widest;
                }

                Repeater {
                    id: rowRepeater
                    model: section.modelData.rows
                    delegate: Row {
                        id: row
                        required property var modelData
                        readonly property real keysWidth: combo.implicitWidth
                        height: card.rowH
                        spacing: Theme.s3

                        Item {
                            width: card.keyColumnWidth
                            height: parent.height
                            KeyCombo {
                                id: combo
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                alts: row.modelData.alts
                            }
                        }
                        LayoutGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: card.anyGlyph
                            label: row.modelData.label
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: Theme.fsBody + 1
                            text: row.modelData.label
                        }
                    }
                }
            }
        }
    }
}
