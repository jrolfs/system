import QtQuick
import Quickshell
import "../../theme"
import "../../services"
import "../../components"

// The HUD's glass capsule: an icon on a tinted tile and one line of text, from OsdState.
// Hud.qml places it on screen and animates it; this is only the look.
Rectangle {
    id: capsule

    height: 52
    width: content.implicitWidth + 2 * 22
    radius: height / 2
    color: Theme.base
    border.width: 1
    border.color: Theme.rim

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.s3

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            height: 26
            visible: OsdState.hudIcon !== ""

            Icon { id: probe; name: OsdState.hudIcon; visible: false }
            Rectangle {
                anchors.fill: parent
                visible: probe.known
                radius: 8
                color: Theme.alpha(Theme.accent, 0.18)
                Icon {
                    anchors.centerIn: parent
                    name: OsdState.hudIcon
                    size: 16
                    color: Theme.accent
                }
            }
            Image {
                anchors.fill: parent
                visible: !probe.known
                source: probe.known || OsdState.hudIcon === "" ? ""
                      : OsdState.hudIcon.startsWith("/") ? "file://" + OsdState.hudIcon
                      : Quickshell.iconPath(OsdState.hudIcon, true)
                sourceSize.width: 52
                sourceSize.height: 52
                fillMode: Image.PreserveAspectFit
                mipmap: true
                asynchronous: true
            }
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: Theme.fsBody + 2
            color: Theme.inkPrimary
            text: OsdState.hudText
        }
    }
}
