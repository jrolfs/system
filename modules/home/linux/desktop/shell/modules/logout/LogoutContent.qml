import QtQuick
import Quickshell
import "../../theme"
import "../../config"
import "../../components"

// Power menu that lives INSIDE the bar island (the island morphs into it, see Bar.qml).
// A row of action tiles, keyboard-navigable (←/→, Enter, Esc). The destructive ones
// (logout/reboot/poweroff) arm on first activation and need a second hit to confirm, so
// one stray Enter can't nuke your session. Logout stops the uwsm session; lock goes to
// LockState via GlobalState; suspend/reboot/poweroff shell out to systemctl. The accent
// marks the selected action; red marks one that's armed and waiting on you to confirm.
Item {
    id: root

    property bool active: false
    implicitHeight: rowItem.height
    clip: true

    readonly property var actions: [
        { id: "lock",     label: "Lock",      icon: "lock",    confirm: false },
        { id: "suspend",  label: "Suspend",   icon: "night",   confirm: false },
        { id: "logout",   label: "Log Out",   icon: "logout",  confirm: true  },
        { id: "reboot",   label: "Reboot",    icon: "restart", confirm: true  },
        { id: "poweroff", label: "Power Off", icon: "power",   confirm: true  }
    ]
    property int index: 0
    property string armed: ""
    onIndexChanged: armed = ""

    function close() { GlobalState.logoutOpen = false; }

    function execute(id) {
        // The session runs under uwsm, and exiting Hyprland directly would skip its
        // shutdown: graphical-session.target and every app unit started in it would stay
        // up with nothing to draw on. `uwsm stop` takes them down in order, Hyprland last.
        // Hyprland's own exit stays as the fallback for a session started without uwsm.
        if (id === "logout")        Quickshell.execDetached(["sh", "-c", "if command -v uwsm >/dev/null && uwsm check is-active >/dev/null 2>&1; then exec uwsm stop; else exec hyprctl dispatch exit; fi"]);
        else if (id === "lock")     GlobalState.requestLock();
        else if (id === "suspend")  Quickshell.execDetached(["systemctl", "suspend"]);
        else if (id === "reboot")   Quickshell.execDetached(["systemctl", "reboot"]);
        else if (id === "poweroff") Quickshell.execDetached(["systemctl", "poweroff"]);
    }

    function activate(i) {
        const a = actions[i];
        if (!a) return;
        if (a.confirm && armed !== a.id) { armed = a.id; return; }   // arm it, then bail and wait for the 2nd hit
        execute(a.id);
        close();
    }

    onActiveChanged: {
        if (active) {
            index = 0;
            armed = "";
            Qt.callLater(() => keyCatcher.forceActiveFocus());
        }
    }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.active
        Keys.onEscapePressed: root.close()
        Keys.onLeftPressed: root.index = Math.max(0, root.index - 1)
        Keys.onRightPressed: root.index = Math.min(root.actions.length - 1, root.index + 1)
        Keys.onReturnPressed: root.activate(root.index)
        Keys.onEnterPressed: root.activate(root.index)
    }

    Row {
        id: rowItem
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.s2
        height: 88

        Repeater {
            model: root.actions
            // Glass tiles: a translucent lift with the rim, the selected one lifted further
            // and carrying the accent in its disc and a keycap for the key that fires it.
            // Armed, the disc and the rim go red and the keycap asks for the second press.
            delegate: Rectangle {
                id: tile
                required property var modelData
                required property int index

                readonly property bool sel: index === root.index
                readonly property bool isArmed: root.armed === modelData.id
                readonly property color mark: isArmed ? Theme.bad : Theme.accent

                width: Math.floor((root.width - Theme.s2 * (root.actions.length - 1)) / root.actions.length)
                height: 88
                radius: Theme.rXl
                color: sel ? Theme.surfaceOverlay : Theme.surfaceBase
                border.width: 1
                border.color: isArmed ? Theme.alpha(Theme.bad, 0.8) : sel ? Theme.alpha(Theme.accent, 0.45) : Theme.rim
                Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                Behavior on border.color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }

                Column {
                    anchors.centerIn: parent
                    spacing: Theme.s2
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 38; height: 38; radius: 19
                        color: tile.sel || tile.isArmed ? tile.mark : Theme.fillLow
                        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                        Icon {
                            anchors.centerIn: parent
                            name: tile.modelData.icon
                            size: 20
                            color: tile.sel || tile.isArmed ? Theme.inkOn(tile.mark) : Theme.inkPrimary
                        }
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        variant: "caption"
                        font.weight: Theme.wMedium
                        text: tile.isArmed ? "Confirm?" : tile.modelData.label
                        color: tile.isArmed ? Theme.bad : tile.sel ? Theme.inkPrimary : Theme.inkDim
                    }
                }

                // ↵ on the selected tile, Raycast's outlined keycap
                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: Theme.s2
                    width: Math.max(20, capText.implicitWidth + 10)
                    height: 20
                    radius: 6
                    color: "transparent"
                    border.width: 1
                    border.color: tile.isArmed ? Theme.alpha(Theme.bad, 0.7) : Theme.hairline
                    opacity: tile.sel ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }
                    StyledText {
                        id: capText
                        anchors.centerIn: parent
                        variant: "caption"
                        text: "↵"
                        color: tile.isArmed ? Theme.bad : Theme.inkDim
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: root.index = tile.index
                    onClicked: root.activate(tile.index)
                }
            }
        }
    }
}
