import QtQuick
import "../../theme"
import "../../components"

// The right-click menu for the connectivity sheets. Lives at the panel level (above the
// sheet and the dimmed grid) so a long list's clip can't cut it off. Items are plain
// objects: { header: true, title, subtitle } for the top line, else { label, act,
// danger, disabled }. Click-away and Esc dismiss; a chosen item runs then dismisses.
Item {
    id: menu
    anchors.fill: parent
    visible: open
    z: 50

    property bool open: false
    property var items: []
    property real ax: 0
    property real ay: 0

    function show(list, x, y) { items = list; ax = x; ay = y; open = true; menu.forceActiveFocus(); }
    function close() { open = false; }

    focus: open
    Keys.onEscapePressed: close()

    // click-away, over everything under the menu
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: menu.close() }

    Rectangle {
        id: card
        readonly property int w: 236
        // opens at the pointer, pulled back inside the panel when it wouldn't fit
        x: Math.max(Theme.s2, Math.min(menu.ax, menu.width - w - Theme.s2))
        y: Math.max(Theme.s2, Math.min(menu.ay, menu.height - height - Theme.s2))
        width: w
        height: col.implicitHeight + Theme.s2 * 2
        radius: Theme.rMd
        // one step lighter than the sheet it floats over, plus a hairline: elevation by fill
        color: Theme.mix(Theme.surfaceOverlay, Theme.foreground, 0.05)
        border.width: 1
        border.color: Theme.hairline
        transformOrigin: Item.TopLeft
        opacity: menu.open ? 1 : 0
        scale: menu.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }
        Behavior on scale { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // clicks inside never reach the click-away

        Column {
            id: col
            x: Theme.s2
            y: Theme.s2
            width: parent.width - Theme.s2 * 2
            Repeater {
                model: menu.items
                delegate: Item {
                    id: it
                    required property var modelData
                    readonly property bool header: !!modelData.header
                    width: col.width
                    height: header ? 44 : 32

                    // header: what this menu is about
                    Column {
                        visible: it.header
                        anchors.left: parent.left; anchors.leftMargin: Theme.s2
                        anchors.right: parent.right; anchors.rightMargin: Theme.s2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        StyledText { width: parent.width; elide: Text.ElideRight; variant: "label"; font.weight: Theme.wMedium; text: it.modelData.title || ""; color: Theme.inkPrimary }
                        StyledText { width: parent.width; elide: Text.ElideRight; variant: "caption"; text: it.modelData.subtitle || ""; color: Theme.inkDim; visible: text !== "" }
                    }
                    Rectangle { visible: it.header; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: Theme.hairline }

                    // action
                    Rectangle {
                        visible: !it.header
                        anchors.fill: parent
                        radius: Theme.rSm
                        color: itMa.containsMouse && !it.modelData.disabled ? Theme.fillLow : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                        StyledText {
                            anchors.left: parent.left; anchors.leftMargin: Theme.s2
                            capCentreIn: parent
                            variant: "label"
                            text: it.modelData.label || ""
                            color: it.modelData.disabled ? Theme.inkFaint : (it.modelData.danger ? Theme.bad : Theme.inkPrimary)
                        }
                        MouseArea {
                            id: itMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !it.modelData.disabled
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { const a = it.modelData.act; menu.close(); if (a) a(); }
                        }
                    }
                }
            }
        }
    }
}
