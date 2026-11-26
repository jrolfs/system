import QtQuick
import Quickshell
import "../../theme"
import "../../services"
import "../../components"
import "../../config"

// Notification content that lives INSIDE the bar island. The island morphs to show this,
// then snaps back (see Bar.qml). Compact: app-icon badge, app name, summary, body.
// `notif` is the one to display. Click dismisses the popup but keeps it in history;
// hovering pauses the auto-dismiss countdown so it won't vanish while you're reading it.
Item {
    id: root

    property var notif: null
    implicitHeight: Math.max(40, ncol.implicitHeight)

    readonly property string nIcon: notif && notif.appIcon
        ? Quickshell.iconPath(notif.appIcon, "dialog-information")
        : (notif && notif.image ? notif.image : "")

    Rectangle {
        id: badge
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 40; height: 40; radius: 20
        color: Theme.fillHigh
        clip: true

        Image {
            anchors.fill: parent
            anchors.margins: 7
            source: root.nIcon
            visible: source != ""
            sourceSize.width: 28
            sourceSize.height: 28
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        // letter-avatar fallback for apps that can't be bothered to send an icon
        StyledText {
            anchors.centerIn: parent
            visible: root.nIcon === ""
            variant: "label"
            font.weight: Theme.wMedium
            text: (root.notif && root.notif.appName) ? root.notif.appName.charAt(0).toUpperCase() : "!"
            color: Theme.accent
        }
    }

    Column {
        id: ncol
        anchors.left: badge.right
        anchors.leftMargin: Theme.s3
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        StyledText {
            width: parent.width
            elide: Text.ElideRight
            variant: "caption"
            visible: text !== ""
            text: root.notif ? (root.notif.appName || "") : ""
            color: Theme.inkDim
        }
        StyledText {
            width: parent.width
            elide: Text.ElideRight
            variant: "label"
            font.weight: Theme.wMedium
            text: root.notif ? (root.notif.summary || "") : ""
            color: Theme.inkPrimary
        }
        StyledText {
            width: parent.width
            elide: Text.ElideRight
            variant: "caption"
            visible: Config.notifShowBody && !!(root.notif && root.notif.body)
            text: root.notif ? (root.notif.body || "") : ""
            textFormat: Text.PlainText
            color: Theme.inkDim
        }
    }

    // click dismisses the popup (history keeps it); hover pauses the countdown
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: Notifications.popupHovered = true
        onExited: Notifications.popupHovered = false
        onClicked: if (root.notif) Notifications.hidePopup(root.notif)
    }
}
