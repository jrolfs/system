import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../theme"
import "../../components"

// Hyprland workspace pills for one screen. Shows the workspaces on this notch's
// monitor, highlights the active one in accent, switches on click.
Row {
    id: root

    required property var screen
    property int pillHeight: 22
    spacing: Theme.s1

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)

    Repeater {
        // Regular workspaces on this monitor, ordered by id. Special/scratchpad ones
        // (negative id) get toggled, not clicked, so leave 'em out.
        model: {
            const mon = root.monitor;
            return Hyprland.workspaces.values
                .filter(w => w.id > 0 && mon && w.monitor && w.monitor.id === mon.id)
                .sort((a, b) => a.id - b.id);
        }

        delegate: Rectangle {
            id: pill
            required property var modelData

            readonly property bool isActive: root.monitor
                && root.monitor.activeWorkspace
                && root.monitor.activeWorkspace.id === modelData.id

            height: root.pillHeight
            width: Math.max(height, label.implicitWidth + Theme.s3)
            radius: Theme.rPill
            color: isActive ? Theme.accent : Theme.glassHigh
            Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }

            StyledText {
                id: label
                anchors.centerIn: parent
                text: pill.modelData.name
                font.pixelSize: Theme.fsLabel
                color: pill.isActive ? Theme.onAccent : Theme.inkDim
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch(`workspace ${pill.modelData.id}`)
            }
        }
    }
}
