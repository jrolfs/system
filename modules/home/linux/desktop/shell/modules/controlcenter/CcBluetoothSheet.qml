import QtQuick
import Quickshell
// qualified: the module's `Bluetooth` singleton would otherwise shadow the services one
import Quickshell.Bluetooth as QB
import "../../theme"
import "../../config"
import "../../services"
import "../../components"

// The Bluetooth btSheet. Three sections the way One UI and Nothing OS lay them out:
// CONNECTED (with battery, drawn with the shell's own battery glyph), SAVED (paired but
// idle, one tap to connect), NEARBY (unpaired devices found while this sheet has the
// adapter discovering; one tap to pair). Device glyphs come from the BlueZ icon names.
Column {
    id: btSheet
    move: CcSheetBits.MoveSpring {}

    property var panel: null
    spacing: Theme.s3

    readonly property var adapter: Bluetooth.adapter
    readonly property bool on: Bluetooth.enabled
    readonly property bool discovering: adapter ? adapter.discovering : false

    // The lists are ScriptModels bound STRAIGHT to Quickshell's device model, the way
    // caelestia / noctalia do it: the binding reads `QB.Bluetooth.devices.values` itself, so
    // the model's own change signal reaches it when BlueZ finds something (a list derived
    // through a helper in the service never re-evaluated, and the keyboard you switched on
    // stayed invisible while bluetoothctl listed it), and ScriptModel diffs by object
    // identity, so rows are not rebuilt on every change. `bonded` is the saved criterion.
    ScriptModel { id: connectedModel; values: QB.Bluetooth.devices.values.filter(d => d.connected).sort((a, b) => (a.name || "").localeCompare(b.name || "")) }
    ScriptModel { id: savedModel;     values: QB.Bluetooth.devices.values.filter(d => d.bonded && !d.connected).sort((a, b) => (a.name || "").localeCompare(b.name || "")) }
    // Nameless devices are left out: in a living room that's every BLE beacon, TV and
    // phone nearby advertising an address and nothing else, and none of them pair from
    // here. Anything mid-pairing stays regardless.
    ScriptModel { id: nearbyModel;    values: QB.Bluetooth.devices.values.filter(d => !d.bonded && ((d.deviceName || "") !== "" || d.pairing)).sort((a, b) => (b.pairing - a.pairing) || (a.name || a.address).localeCompare(b.name || b.address)) }
    readonly property int connectedCount: connectedModel.values.length
    readonly property int savedCount: savedModel.values.length
    readonly property int nearbyCount: nearbyModel.values.length

    // discovery runs only while this sheet is showing: it is radio-noisy and costs battery
    onVisibleChanged: if (adapter && adapter.enabled) adapter.discovering = visible
    Connections { target: btSheet.adapter; function onEnabledChanged() { if (btSheet.visible && btSheet.adapter) btSheet.adapter.discovering = btSheet.adapter.enabled; } }

    function glyph(d) {
        const i = (d.icon || "").toLowerCase();
        if (i.indexOf("headset") >= 0 || i.indexOf("headphone") >= 0) return "headphones";
        if (i.indexOf("phone") >= 0) return "phone";
        if (i.indexOf("keyboard") >= 0) return "keyboard";
        if (i.indexOf("mouse") >= 0) return "mouse";
        if (i.indexOf("watch") >= 0) return "watch";
        if (i.indexOf("audio") >= 0 || i.indexOf("speaker") >= 0) return "volume";
        if (i.indexOf("gaming") >= 0 || i.indexOf("joystick") >= 0) return "controller";
        if (i.indexOf("computer") >= 0 || i.indexOf("laptop") >= 0 || i.indexOf("display") >= 0) return "display";
        return "bluetooth";
    }
    function label(d) { return d.deviceName || d.name || d.address; }
    function busy(d) { return d.pairing || d.state === QB.BluetoothDeviceState.Connecting || d.state === QB.BluetoothDeviceState.Disconnecting; }
    function status(d) {
        if (d.pairing) return "Pairing…";
        if (d.state === QB.BluetoothDeviceState.Connecting) return "Connecting…";
        if (d.state === QB.BluetoothDeviceState.Disconnecting) return "Disconnecting…";
        if (d.connected) return "Connected";
        return d.bonded ? "Saved" : "Not paired";
    }

    // the right-click menu for a device
    function menuFor(d, item, x, y) {
        const items = [{ header: true, title: label(d),
                         subtitle: d.address + (d.connected && d.batteryAvailable ? "  ·  " + Math.round(d.battery * 100) + "%" : "") }];
        if (d.connected) items.push({ label: "Disconnect", act: () => d.disconnect() });
        else if (d.bonded) items.push({ label: "Connect", act: () => d.connect() });
        else if (d.pairing) items.push({ label: "Cancel pairing", act: () => d.cancelPair() });
        else items.push({ label: "Pair", act: () => Bluetooth.pairAndConnect(d) });
        if (d.bonded) items.push({ label: d.trusted ? "Untrust device" : "Trust device", act: () => { d.trusted = !d.trusted; } });
        if (d.bonded) items.push({ label: "Forget device", danger: true, act: () => d.forget() });
        items.push({ label: "Copy address", act: () => { Quickshell.clipboardText = d.address; } });
        panel.openMenu(items, item, x, y);
    }

    // one device row, used by all three sections
    component DeviceRow: Rectangle {
        id: r
        property var d: null
        property string verb: ""            // what the chip offers
        signal act()
        width: parent ? parent.width : 0
        height: 52
        radius: Theme.rSm + 2
        // rows sit straight on the pane, Raycast's list form: only the hovered one fills
        color: rMa.containsMouse ? Theme.selection : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
        opacity: entered
        // delegate-owned entrance (patterns.md #5): a positioner `add` transition is cancelled
        // by the next relayout and strands the row at opacity 0
        property real entered: 0
        Component.onCompleted: entered = 1
        Behavior on entered { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
        MouseArea {
            id: rMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => { if (m.button === Qt.RightButton) btSheet.menuFor(r.d, r, m.x, m.y); else r.act(); }
        }

        CcSheetBits.Disc { tint: Theme.hue("toggles");
            id: dDisc
            anchors.left: parent.left
            anchors.leftMargin: Theme.s2
            anchors.verticalCenter: parent.verticalCenter
            size: 36
            live: r.d.connected
            icon: btSheet.glyph(r.d)
        }
        Column {
            anchors.left: dDisc.right
            anchors.leftMargin: Theme.s3
            anchors.right: chip.left
            anchors.rightMargin: Theme.s2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            StyledText {
                width: parent.width; elide: Text.ElideRight
                variant: "label"; font.weight: Theme.wMedium
                text: btSheet.label(r.d)
                color: Theme.inkPrimary
            }
            Row {
                spacing: Theme.s2
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    variant: "caption"
                    text: btSheet.status(r.d)
                    color: btSheet.busy(r.d) ? Theme.hue("toggles") : Theme.inkDim
                }
                BatteryGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: r.d.connected && r.d.batteryAvailable
                    level: r.d.battery
                    low: r.d.battery <= 0.2
                    size: 13
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: r.d.connected && r.d.batteryAvailable
                    variant: "caption"
                    text: Math.round(r.d.battery * 100) + "%"
                    color: Theme.inkDim
                }
            }
        }
        CcSheetBits.Chip { tint: Theme.hue("toggles");
            id: chip
            anchors.right: parent.right
            anchors.rightMargin: Theme.s2
            anchors.verticalCenter: parent.verticalCenter
            text: r.verb
            accent: !r.d.connected
            // a second press mid-connect would queue a disconnect behind it
            enabledLook: !btSheet.busy(r.d) || r.d.pairing
            onClicked: r.act()
        }
    }

    // ── off, or no adapter at all ──
    Rectangle {
        visible: !btSheet.on
        width: parent.width
        height: 72
        opacity: visible ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
        radius: Theme.rLg
        color: Theme.surfaceBase
        border.width: 1
        border.color: Theme.rim
        CcSheetBits.Disc { tint: Theme.hue("toggles"); id: offDisc; anchors.left: parent.left; anchors.leftMargin: Theme.s3; anchors.verticalCenter: parent.verticalCenter; size: 44; icon: "bluetooth" }
        Column {
            anchors.left: offDisc.right; anchors.leftMargin: Theme.s3; anchors.right: parent.right; anchors.rightMargin: Theme.s3
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            StyledText { variant: "body"; font.weight: Theme.wMedium; text: Bluetooth.available ? "Bluetooth is off" : "No Bluetooth adapter"; color: Theme.inkPrimary }
            StyledText { variant: "caption"; text: Bluetooth.available ? "Turn it on to see your devices" : "BlueZ isn't reporting one"; color: Theme.inkDim }
        }
    }

    // ── connected ──
    CcSheetBits.SectionLabel { visible: btSheet.on && btSheet.connectedCount > 0; text: "Connected"; opacity: visible ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } } }
    Column {
        visible: btSheet.on && btSheet.connectedCount > 0
        width: parent.width
        spacing: Theme.s1
        move: CcSheetBits.MoveSpring {}
        Repeater {
            model: connectedModel
            delegate: DeviceRow { required property var modelData; d: modelData; verb: "Disconnect"; onAct: modelData.disconnect() }
        }
    }

    // ── saved ──
    CcSheetBits.SectionLabel { visible: btSheet.on && btSheet.savedCount > 0; text: "Saved"; opacity: visible ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } } }
    Column {
        visible: btSheet.on && btSheet.savedCount > 0
        width: parent.width
        spacing: Theme.s1
        move: CcSheetBits.MoveSpring {}
        Repeater {
            model: savedModel
            delegate: DeviceRow { required property var modelData; d: modelData; verb: "Connect"; onAct: modelData.connect() }
        }
    }

    // ── nearby ──
    CcSheetBits.SectionLabel { visible: btSheet.on; text: "Nearby"; busy: btSheet.discovering; opacity: visible ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } } }
    Column {
        visible: btSheet.on && btSheet.nearbyCount > 0
        width: parent.width
        spacing: Theme.s1
        move: CcSheetBits.MoveSpring {}
        Repeater {
            model: nearbyModel
            delegate: DeviceRow { required property var modelData; d: modelData; verb: modelData.pairing ? "Cancel" : "Pair"; onAct: modelData.pairing ? modelData.cancelPair() : Bluetooth.pairAndConnect(modelData) }
        }
    }
    StyledText {
        visible: btSheet.on && btSheet.nearbyCount === 0
        opacity: visible ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
        variant: "label"
        text: btSheet.discovering ? "Looking for devices…  put the device in pairing mode" : "Nothing nearby"
        color: Theme.inkDim
    }
}
