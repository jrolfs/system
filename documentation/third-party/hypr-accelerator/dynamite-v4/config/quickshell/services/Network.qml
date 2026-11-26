pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking

// Active network summary. Quickshell.Networking is NetworkManager-backed and still pretty
// young (gotcha #10): covers wifi/wired fine, fall back to nmcli only for what it misses.
Singleton {
    id: root

    // Networking's list props are ObjectModels (read .values), so coerce defensively.
    function asArray(m) { return !m ? [] : (m.values !== undefined ? m.values : m); }

    readonly property var devices: asArray(Networking.devices)
    readonly property var activeDevice: devices.find(d => d.connected) ?? null
    readonly property bool connected: activeDevice !== null
    readonly property bool wifiEnabled: Networking.wifiEnabled

    readonly property bool isWifi: activeDevice ? activeDevice.type === DeviceType.Wifi : false
    readonly property bool isWired: activeDevice ? activeDevice.type === DeviceType.Wired : false

    readonly property var activeWifi: {
        if (!isWifi)
            return null;
        return asArray(activeDevice.networks).find(n => n.connected) ?? null;
    }
    readonly property string ssid: activeWifi ? activeWifi.name : ""
    readonly property real signalStrength: activeWifi ? activeWifi.signalStrength : 0   // 0..1, NOT int. int truncates 0.69 to 0 and the meter flatlines

    readonly property string label: {
        if (isWired) return "Ethernet";
        if (isWifi) return ssid !== "" ? ssid : "Wi-Fi";
        return "Offline";
    }

    function toggleWifi() { Networking.wifiEnabled = !Networking.wifiEnabled; }
    function setWifiEnabled(on) { Networking.wifiEnabled = on; }

    // --- Wi-Fi network browsing (control center list) ---
    readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi) ?? null
    // same insurance as the Bluetooth service: networks that appear mid-scan may not notify a
    // binding, so the list re-reads on a 1s tick while the scanner is on
    property int rev: 0
    Timer { interval: 1000; repeat: true; running: root.wifiDevice ? root.wifiDevice.scannerEnabled : false; onTriggered: root.rev++ }
    readonly property var wifiNetworks: {
        rev;
        return wifiDevice
            ? asArray(wifiDevice.networks).slice().sort((a, b) => (b.signalStrength || 0) - (a.signalStrength || 0))
            : [];
    }

    // Toggle background scanning on/off (we turn it on while the network list is open).
    function setScanning(on) { if (wifiDevice) wifiDevice.scannerEnabled = on; }
}
