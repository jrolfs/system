import QtQuick
import Quickshell
import "../../theme"
import "../../config"
import "../../services"
import "../../components"

// Notification history as a card. Always full width; its HEIGHT is the size lever (1 to
// 4 rows): a header row with "Clear all", then as much of the list as fits, clipped.
Item {
    id: tile

    property var ctl: null
    readonly property bool interactive: ctl ? ctl.interactive : true

    Rectangle {
        anchors.fill: parent
        radius: Theme.rXl
        color: Theme.surfaceOverlay
    }


    // Hairline rim (Tahoe's glass edge, without the glass): a 1px stroke in the ink colour at
    // hairline alpha, drawn ON TOP so hover veils and album art never soften it. It is what
    // separates a tile from the black island without any glow.
    Rectangle {
        anchors.fill: parent
        radius: Theme.rXl
        color: "transparent"
        border.width: 1
        border.color: Theme.rim
        z: 5
    }

    Item {
        id: head
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Theme.s3; leftMargin: Theme.s4; rightMargin: Theme.s4 }
        height: 18
        StyledText {
            anchors.left: parent.left; capCentreIn: parent
            variant: "caption"; text: "Notifications"; color: Theme.inkDim
        }
        StyledText {
            anchors.right: parent.right; capCentreIn: parent
            visible: Notifications.list.length > 0
            variant: "caption"; text: "Clear all"; color: clearMa.containsMouse ? Theme.accent : Theme.inkDim
            Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
            MouseArea { id: clearMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; enabled: tile.interactive; cursorShape: Qt.PointingHandCursor; onClicked: Notifications.clearAll() }
        }
    }

    StyledText {
        visible: Notifications.list.length === 0
        anchors { top: head.bottom; left: parent.left; topMargin: Theme.s2; leftMargin: Theme.s4 }
        variant: "label"; text: "No notifications"; color: Theme.inkDim
    }

    ListView {
        visible: Notifications.list.length > 0
        anchors { top: head.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; topMargin: Theme.s2; leftMargin: Theme.s3; rightMargin: Theme.s3; bottomMargin: Theme.s3 }
        clip: true
        spacing: Theme.s1
        model: Notifications.list
        boundsBehavior: Flickable.StopAtBounds
        interactive: tile.interactive
        delegate: Rectangle {
            id: hrow
            required property var modelData
            width: ListView.view.width
            height: hcol.implicitHeight + Theme.s3 * 2
            radius: Theme.rLg
            color: Theme.fillLow

            readonly property string nIcon: modelData.appIcon
                ? Quickshell.iconPath(modelData.appIcon, "dialog-information")
                : (modelData.image || "")

            Rectangle {
                id: nbadge
                anchors.left: parent.left; anchors.top: parent.top
                anchors.leftMargin: Theme.s3; anchors.topMargin: Theme.s3
                width: 32; height: 32; radius: 16
                color: hrow.nIcon !== "" ? Theme.fillHigh : Theme.alpha(Theme.accent, 0.18)
                clip: true
                Image {
                    anchors.fill: parent; anchors.margins: 5
                    source: hrow.nIcon; visible: source != ""
                    sourceSize.width: 24; sourceSize.height: 24
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                StyledText {
                    anchors.centerIn: parent
                    visible: hrow.nIcon === ""
                    variant: "caption"
                    font.weight: Theme.wMedium
                    text: (hrow.modelData.appName || "?").charAt(0).toUpperCase()
                    color: Theme.accent
                }
            }
            Column {
                id: hcol
                anchors.left: nbadge.right; anchors.leftMargin: Theme.s3
                anchors.right: hclose.left; anchors.rightMargin: Theme.s2
                anchors.top: parent.top; anchors.topMargin: Theme.s3
                spacing: 1
                StyledText { width: parent.width; elide: Text.ElideRight; variant: "caption"; visible: text !== ""; text: hrow.modelData.appName || ""; color: Theme.inkDim }
                StyledText { width: parent.width; elide: Text.ElideRight; variant: "label"; font.weight: Theme.wMedium; text: hrow.modelData.summary || ""; color: Theme.inkPrimary }
                StyledText { width: parent.width; visible: (hrow.modelData.body || "") !== ""; elide: Text.ElideRight; variant: "caption"; text: hrow.modelData.body; textFormat: Text.PlainText; color: Theme.inkDim }
            }
            StyledText {
                id: hclose
                anchors.right: parent.right; anchors.top: parent.top
                anchors.rightMargin: Theme.s3; anchors.topMargin: Theme.s3
                text: "✕"
                color: Theme.inkDim
                MouseArea { anchors.fill: parent; anchors.margins: -6; enabled: tile.interactive; cursorShape: Qt.PointingHandCursor; onClicked: Notifications.dismiss(hrow.modelData) }
            }
        }
    }
}
