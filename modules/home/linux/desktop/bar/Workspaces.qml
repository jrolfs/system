import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

// This monitor's numbered workspaces. Special workspaces (the ⌥Tab terminal
// and ⌥` notes) have negative ids and are left out: they're overlays, not
// places.
RowLayout {
  required property var monitor

  spacing: 4

  Repeater {
    model: Hyprland.workspaces.values.filter(workspace => workspace.id > 0 && workspace.monitor === monitor)

    Rectangle {
      required property var modelData

      readonly property bool current: modelData.active

      implicitWidth: Math.max(label.implicitWidth + 12, height)
      implicitHeight: Theme.height - 12
      radius: Theme.rounding
      color: current ? Theme.accent : modelData.urgent ? Theme.urgent : "transparent"

      Text {
        id: label
        anchors.centerIn: parent
        text: modelData.name
        color: parent.current ? Theme.accentForeground : Theme.foreground
        font.family: Theme.sans
        font.pixelSize: Theme.fontSize
        font.weight: parent.current ? Font.DemiBold : Font.Normal
      }

      MouseArea {
        anchors.fill: parent
        onClicked: modelData.activate()
      }
    }
  }
}
