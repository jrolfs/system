import Quickshell
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts

// Bluetooth: off, on, or connected (with the number of devices when more
// than one). Click to open the pairing UI.
Item {
  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool enabled: adapter?.enabled ?? false
  readonly property int connected: Bluetooth.devices.values.filter(device => device.connected).length

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  RowLayout {
    id: row
    spacing: 4

    Icon {
      // bluetooth-slash, bluetooth-connected, bluetooth
      glyph: !enabled ? "\ue0de" : connected > 0 ? "\ue0dc" : "\ue0da"
      color: enabled ? Theme.foreground : Theme.muted
    }

    Text {
      visible: connected > 1
      text: connected
      color: Theme.foreground
      font.family: Theme.sans
      font.pixelSize: Theme.fontSize
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: Quickshell.execDetached(["blueman-manager"])
  }
}
