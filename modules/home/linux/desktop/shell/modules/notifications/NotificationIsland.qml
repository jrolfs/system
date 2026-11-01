import QtQuick
import Quickshell
import "../../theme"
import "../../services"
import "../../components"
import "../../config"

// The notification the island morphs to show, then lets go of (see Bar.qml): an app icon
// tile, the app name, the summary, up to three lines of body (markup rendered, links
// open), and the sender's actions as small buttons. A click on the card runs the default
// action when there is one; either way the popup goes and history keeps it. Hovering
// holds the auto-dismiss countdown so it can't vanish mid-read.
Item {
    id: root

    property var notif: null
    implicitHeight: Math.max(badge.height, ncol.implicitHeight)

    function resolve(s) {
        if (!s) return "";
        if (s.startsWith("/")) return "file://" + s;
        if (s.indexOf("://") >= 0) return s;
        return Quickshell.iconPath(s, true);
    }
    // the app's own icon first, then whatever image came with it
    readonly property string nIcon: notif ? (resolve(notif.appIcon) || resolve(notif.image)) : ""

    readonly property var actions: notif && notif.actions ? Array.from(notif.actions) : []
    readonly property var defaultAction: actions.find(a => a.identifier === "default") ?? null
    readonly property var buttons: actions.filter(a => a.identifier !== "default" && a.text !== "")

    function finish() { if (root.notif) Notifications.hidePopup(root.notif); }

    HoverHandler {
        onHoveredChanged: Notifications.popupHovered = hovered
    }

    // the card itself: default action, or just dismiss the popup
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const n = root.notif;
            if (root.defaultAction) root.defaultAction.invoke();
            if (n) Notifications.hidePopup(n);
        }
    }

    Rectangle {
        id: badge
        anchors.left: parent.left
        anchors.top: parent.top
        width: 40; height: 40
        radius: Theme.rRow
        color: Theme.fillLow
        clip: true

        Image {
            id: badgeImg
            anchors.fill: parent
            anchors.margins: 5
            source: root.nIcon
            visible: source != "" && status !== Image.Error
            sourceSize.width: 60
            sourceSize.height: 60
            fillMode: Image.PreserveAspectFit
            mipmap: true
            asynchronous: true
        }
        // letter tile for senders that send no icon
        StyledText {
            anchors.centerIn: parent
            visible: !badgeImg.visible
            variant: "body"
            font.weight: Theme.wSemiBold
            text: (root.notif && root.notif.appName) ? root.notif.appName.charAt(0).toUpperCase() : "!"
            color: Theme.accent
        }
    }

    Column {
        id: ncol
        anchors.left: badge.right
        anchors.leftMargin: Theme.s3 + 2
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 2

        StyledText {
            width: parent.width
            elide: Text.ElideRight
            variant: "caption"
            font.weight: Theme.wMedium
            visible: text !== ""
            text: root.notif ? (root.notif.appName || "") : ""
            color: Theme.inkDim
        }
        StyledText {
            width: parent.width
            elide: Text.ElideRight
            variant: "body"
            font.weight: Theme.wMedium
            text: root.notif ? (root.notif.summary || "") : ""
            color: Theme.inkPrimary
        }
        StyledText {
            width: parent.width
            visible: Config.notifShowBody && !!(root.notif && root.notif.body)
            variant: "label"
            // the server advertises body markup, so senders send the spec's small HTML
            // subset (b, i, u, a, img); StyledText renders it without the cost of rich text
            text: root.notif ? (root.notif.body || "") : ""
            textFormat: Text.StyledText
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            color: Theme.inkSecondary
            linkColor: Theme.accent
            onLinkActivated: link => { Qt.openUrlExternally(link); root.finish(); }
        }

        Item { width: 1; height: root.buttons.length > 0 ? Theme.s2 : 0 }

        Row {
            visible: root.buttons.length > 0
            spacing: Theme.s2
            Repeater {
                model: root.buttons
                delegate: Rectangle {
                    id: btn
                    required property var modelData
                    height: 28
                    width: btnLabel.implicitWidth + Theme.s4 * 2
                    radius: height / 2
                    color: btnMa.containsMouse ? Theme.fillHigh : Theme.fillLow
                    border.width: 1
                    border.color: Theme.rim
                    Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                    StyledText {
                        id: btnLabel
                        anchors.centerIn: parent
                        variant: "label"
                        font.weight: Theme.wMedium
                        text: btn.modelData.text
                        color: Theme.inkPrimary
                    }
                    MouseArea {
                        id: btnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const n = root.notif;
                            btn.modelData.invoke();
                            if (n) Notifications.hidePopup(n);
                        }
                    }
                }
            }
        }
    }
}
