pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Active network summary. Quickshell.Networking is NetworkManager-backed and still pretty
// young (gotcha #10): covers wifi/wired fine, fall back to nmcli only for what it misses.
//
// A host without NetworkManager (irulan: wired, plain DHCP from networkd) has no devices
// here at all, which used to read as "Offline" on a machine that was online. There the
// kernel's routing table answers instead: a default route through an interface means
// connected, and the interface's name says whether it's wired.
Singleton {
    id: root

    // Networking's list props are ObjectModels (read .values), so coerce defensively.
    function asArray(m) { return !m ? [] : (m.values !== undefined ? m.values : m); }

    readonly property var devices: asArray(Networking.devices)
    readonly property bool managed: devices.length > 0
    readonly property var activeDevice: devices.find(d => d.connected) ?? null
    readonly property bool connected: managed ? activeDevice !== null : routeIface !== ""
    readonly property bool wifiEnabled: wifiAvailable && Networking.wifiEnabled

    readonly property bool isWifi: managed ? (activeDevice ? activeDevice.type === DeviceType.Wifi : false)
                                           : /^wl/.test(routeIface)
    readonly property bool isWired: managed ? (activeDevice ? activeDevice.type === DeviceType.Wired : false)
                                            : /^(en|eth)/.test(routeIface)

    readonly property var activeWifi: {
        if (!isWifi || !activeDevice)
            return null;
        return asArray(activeDevice.networks).find(n => n.connected) ?? null;
    }
    readonly property string ssid: activeWifi ? activeWifi.name : ""
    readonly property real signalStrength: activeWifi ? activeWifi.signalStrength : 0   // 0..1, NOT int. int truncates 0.69 to 0 and the meter flatlines

    readonly property string label: {
        if (isWired) return "Ethernet";
        if (isWifi) return ssid !== "" ? ssid : "Wi-Fi";
        if (connected) return "Connected";
        return "Offline";
    }

    function toggleWifi() { if (wifiAvailable) Networking.wifiEnabled = !Networking.wifiEnabled; }
    function setWifiEnabled(on) { if (wifiAvailable) Networking.wifiEnabled = on; }

    // --- Wi-Fi network browsing (control center list) ---
    readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi) ?? null
    // false without NetworkManager or without a Wi-Fi radio; the Wi-Fi controls disable
    readonly property bool wifiAvailable: wifiDevice !== null
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

    // --- unmanaged fallback: the interface carrying the default route, "" if none ---
    property string routeIface: ""
    FileView {
        id: routes
        path: "/proc/net/route"
        // procfs files report size 0 and never emit change notifications, so this is read
        // whole on a timer rather than watched
        blockLoading: true
        onLoaded: {
            let iface = "";
            for (const line of text().split("\n").slice(1)) {
                const f = line.trim().split(/\s+/);
                // destination 0.0.0.0 with mask 0.0.0.0 is the default route; virtual
                // bridges (docker, libvirt) can carry one too but never the only one
                if (f.length >= 8 && f[1] === "00000000" && f[7] === "00000000" && !/^(docker|br-|veth|virbr|lo)/.test(f[0])) {
                    iface = f[0];
                    break;
                }
            }
            root.routeIface = iface;
        }
    }
    Timer {
        interval: 5000
        repeat: true
        running: !root.managed
        triggeredOnStart: true
        onTriggered: routes.reload()
    }
}
