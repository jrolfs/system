import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../theme"
import "../../config"
import "../../components"

// Power menu that lives INSIDE the bar island (the island morphs into it, see Bar.qml).
// A row of action tiles, keyboard-navigable (←/→, Enter, Esc). The destructive ones
// (logout/reboot/poweroff) arm on first activation and need a second hit to confirm, so
// one stray Enter can't nuke your session. Logout exits Hyprland; lock goes to LockState
// via GlobalState; suspend/reboot/poweroff shell out to systemctl. The accent marks the
// selected action; red marks one that's armed and waiting on you to confirm.
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
        if (id === "logout")        Hyprland.dispatch("exit");
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
            delegate: Rectangle {
                id: tile
                required property var modelData
                required property int index

                readonly property bool sel: index === root.index
                readonly property bool isArmed: root.armed === modelData.id

                width: Math.floor((root.width - Theme.s2 * (root.actions.length - 1)) / root.actions.length)
                height: 88
                radius: Theme.rXl
                color: sel ? Theme.accent : Theme.surfaceOverlay
                border.color: isArmed ? Theme.bad : "transparent"
                border.width: isArmed ? 2 : 0
                Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                Behavior on border.color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }

                Column {
                    anchors.centerIn: parent
                    spacing: Theme.s1
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: tile.modelData.icon
                        size: 24
                        color: tile.sel ? Theme.onAccent : Theme.inkPrimary
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        variant: "caption"
                        font.weight: Theme.wMedium
                        text: tile.isArmed ? "Confirm?" : tile.modelData.label
                        color: tile.isArmed && !tile.sel ? Theme.bad
                             : tile.sel ? Theme.onAccent : Theme.inkPrimary
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
