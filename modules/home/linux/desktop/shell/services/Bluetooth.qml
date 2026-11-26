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
    // false with no adapter at all (or BlueZ not running); the controls disable
    readonly property bool available: adapter !== null
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
        if (!available) return "Unavailable";
        if (!enabled) return "Off";
        if (connectedDevices.length === 0) return "On";
        if (connectedDevices.length === 1) {
            const d = connectedDevices[0];
            return d.name || d.deviceName || "1 device";
        }
        return `${connectedDevices.length} devices`;
    }

    function toggle() { if (adapter) adapter.enabled = !adapter.enabled; }
    function setEnabled(on) { if (adapter) adapter.enabled = on; }

    // Paired devices for the control center list, connected ones up top.
    readonly property var pairedDevices: devicesNow()
        .filter(d => d.paired)
        .slice()
        .sort((a, b) => (b.connected ? 1 : 0) - (a.connected ? 1 : 0))

    // Pair, trust, then connect. BlueZ's Pair() leaves an input device bonded but not
    // connected, and an untrusted one is refused when it tries to reconnect on its own
    // after a sleep, which for a keyboard or a controller is the whole point. The
    // connect waits for the bond to land, polled because the device object can move
    // between lists (and delegates) while pairing runs.
    property var _awaitingBond: []
    function pairAndConnect(d) {
        if (!d) return;
        d.trusted = true;
        d.pair();
        if (!_awaitingBond.some(e => e.device === d)) _awaitingBond = _awaitingBond.concat([{ device: d, since: Date.now() }]);
        bondPoll.start();
    }
    Timer {
        id: bondPoll
        interval: 500
        repeat: true
        onTriggered: {
            const now = Date.now();
            root._awaitingBond = root._awaitingBond.filter(e => {
                const d = e.device;
                if (!d) return false;
                if (d.bonded || d.paired) {
                    if (!d.connected) d.connect();
                    return false;
                }
                // pairing gave up (cancelled, refused, timed out in BlueZ)
                return d.pairing || now - e.since < 3000 ? now - e.since < 60000 : false;
            });
            if (root._awaitingBond.length === 0) stop();
        }
    }
}
