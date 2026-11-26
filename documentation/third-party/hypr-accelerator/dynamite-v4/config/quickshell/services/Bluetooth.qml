pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Bluetooth summary. Quickshell.Bluetooth (BlueZ) covers power, connect/disconnect,
// info, and basic pairing. Anything fancier and yer back to bluetoothctl (gotcha #10).
Singleton {
    id: root

    function asArray(m) { return !m ? [] : (m.values !== undefined ? m.values : m); }

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter ? adapter.enabled : false
    // Devices BlueZ finds while discovering land in Bluetooth.devices, but no change signal
    // reaches a QML BINDING for those insertions (fresh reads see them, bindings don't), so
    // anything derived from the model froze at whatever existed at startup: a new pair of
    // earbuds in pairing mode never showed up. `rev` is bumped by the model's own signals
    // AND by a 1s tick while discovery runs, and every derived list reads through it.
    property int rev: 0
    Connections {
        target: Bluetooth.devices
        function onValuesChanged() { root.rev++; }
        function onObjectInsertedPost() { root.rev++; }
        function onObjectRemovedPost() { root.rev++; }
    }
    Timer { interval: 1000; repeat: true; running: root.adapter ? root.adapter.discovering : false; onTriggered: root.rev++ }
    function devicesNow() { rev; return asArray(Bluetooth.devices); }

    readonly property var connectedDevices: devicesNow().filter(d => d.connected)
    readonly property bool hasConnection: connectedDevices.length > 0

    readonly property string label: {
        if (!enabled) return "BT off";
        if (connectedDevices.length === 0) return "BT on";
        if (connectedDevices.length === 1) {
            const d = connectedDevices[0];
            return d.deviceName || d.name || "BT";
        }
        return `BT ×${connectedDevices.length}`;
    }

    function toggle() { if (adapter) adapter.enabled = !adapter.enabled; }
    function setEnabled(on) { if (adapter) adapter.enabled = on; }

    // Paired devices for the control center list, connected ones up top.
    readonly property var pairedDevices: devicesNow()
        .filter(d => d.paired)
        .slice()
        .sort((a, b) => (b.connected ? 1 : 0) - (a.connected ? 1 : 0))
}
