import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

PanelWindow {
  id: bar

  anchors {
    top: true
    left: true
    right: true
  }

  implicitHeight: Theme.height
  color: "transparent"

  // Hyprland's layer rule matches on this to blur behind the bar.
  WlrLayershell.namespace: "quickshell:bar"

  readonly property var monitor: Hyprland.monitorFor(screen)

  Rectangle {
    anchors.fill: parent
    color: Theme.background
  }

  RowLayout {
    anchors {
      left: parent.left
      verticalCenter: parent.verticalCenter
      leftMargin: Theme.padding
    }
    spacing: Theme.spacing

    Workspaces {
      monitor: bar.monitor
    }

    Text {
      Layout.maximumWidth: bar.width / 3
      text: Hyprland.activeToplevel?.title ?? ""
      elide: Text.ElideRight
      color: Theme.foreground
      font.family: Theme.sans
      font.pixelSize: Theme.fontSize
    }
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  Text {
    anchors.centerIn: parent
    text: Qt.formatDateTime(clock.date, "ddd MMM d  h:mm AP")
    color: Theme.foreground
    font.family: Theme.sans
    font.pixelSize: Theme.fontSize
  }

  RowLayout {
    anchors {
      right: parent.right
      verticalCenter: parent.verticalCenter
      rightMargin: Theme.padding
    }
    spacing: Theme.spacing

    Audio {}
    BluetoothStatus {}
  }
}
