import QtQuick
import Quickshell
// Qualified on purpose: Quickshell.Networking exports a TYPE called `Network`, which would
// shadow the services singleton of the same name in this file and turn every Network.*
// read into undefined (the sheet showed "Wi-Fi is off" beside a toggle that said on).
import Quickshell.Networking as QN
import "../../theme"
import "../../config"
import "../../services"
import "../../components"

// The Wi-Fi wifiSheet. Tahoe's shape (the network you're on, then the rest) with Android's
// hero card for the live connection. Rows carry what the network actually is: signal,
// security, whether it's saved, and "Connecting..." while NetworkManager works. Joining an
// unknown secured network opens the password field INLINE under that row, the way macOS
// does it, instead of a field parked at the bottom of the list.
Column {
    id: wifiSheet

    property var panel: null            // the control center root (pskTarget lives there)
    spacing: Theme.s3

    readonly property var live: Network.activeWifi
    readonly property bool on: Network.wifiEnabled
    // The list shows the five strongest networks (the service already sorts by signal) and
    // folds the rest behind "See all": a full scan around here is a dozen-plus SSIDs and the
    // ones you want are almost always at the top. Resets when the sheet closes.
    readonly property int shownMax: 5
    property bool showAll: false
    readonly property int liveIndex: Network.wifiNetworks.findIndex(n => n.connected)
    readonly property int listable: Network.wifiNetworks.length - (liveIndex >= 0 ? 1 : 0)
    readonly property int hidden: Math.max(0, listable - shownMax)
    onVisibleChanged: if (!visible) showAll = false
    readonly property bool scanning: Network.wifiDevice ? Network.wifiDevice.scannerEnabled : false

    function secured(net) { return net.security !== QN.WifiSecurityType.Open && net.security !== QN.WifiSecurityType.Owe && net.security !== QN.WifiSecurityType.Unknown; }
    function secLabel(net) {
        const t = net.security;
        if (t === QN.WifiSecurityType.Open) return "Open";
        if (t === QN.WifiSecurityType.Owe) return "Enhanced Open";
        if (t === QN.WifiSecurityType.Sae || t === QN.WifiSecurityType.Wpa3SuiteB192) return "WPA3";
        if (t === QN.WifiSecurityType.Wpa2Psk) return "WPA2";
        if (t === QN.WifiSecurityType.WpaPsk) return "WPA";
        if (t === QN.WifiSecurityType.Wpa2Eap || t === QN.WifiSecurityType.WpaEap || t === QN.WifiSecurityType.Leap) return "Enterprise";
        if (t === QN.WifiSecurityType.StaticWep || t === QN.WifiSecurityType.DynamicWep) return "WEP";
        return "";
    }
    // the right-click menu for a network (rows and the hero alike)
    function menuFor(net, item, x, y) {
        const sec = secLabel(net), sig = Math.round(net.signalStrength * 100);
        const items = [{ header: true, title: (net.name && net.name !== "") ? net.name : "(hidden network)",
                         subtitle: sec + "  ·  " + sig + "% signal  ·  " + (net.connected ? "Connected" : net.known ? "Saved" : "Not saved") }];
        if (net.connected) items.push({ label: "Disconnect", act: () => net.disconnect() });
        else if (net.known || !secured(net)) items.push({ label: "Connect", act: () => net.connect() });
        else items.push({ label: "Join with password…", act: () => { panel.pskTarget = net; } });
        if (net.known) items.push({ label: "Forget network", danger: true, act: () => net.forget() });
        items.push({ label: "Copy network name", disabled: !(net.name && net.name !== ""), act: () => { Quickshell.clipboardText = net.name; } });
        panel.openMenu(items, item, x, y);
    }
    function press(net) {
        if (net.connected) { net.disconnect(); return; }
        if (net.known || !secured(net)) { panel.pskTarget = null; net.connect(); return; }
        panel.pskTarget = (panel.pskTarget === net) ? null : net;
    }

    // ── hero: what you're on right now ──────────────────────────────────────────────
    Rectangle {
        id: hero
        width: parent.width
        height: 72
        radius: Theme.rLg
        color: Theme.surfaceBase
        border.width: 1
        border.color: Theme.rim
        MouseArea {   // right-click the hero for the live network's menu
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: m => { if (wifiSheet.live) wifiSheet.menuFor(wifiSheet.live, hero, m.x, m.y); }
        }

        CcSheetBits.Disc { tint: Theme.hue("toggles");
            id: heroDisc
            anchors.left: parent.left
            anchors.leftMargin: Theme.s3
            anchors.verticalCenter: parent.verticalCenter
            size: 44
            live: wifiSheet.on && !!wifiSheet.live
            WifiIcon {
                anchors.centerIn: parent
                active: wifiSheet.on && !!wifiSheet.live
                strength: wifiSheet.live ? wifiSheet.live.signalStrength : 0
                color: heroDisc.live ? Theme.onAccent : Theme.inkPrimary
                dimColor: heroDisc.live ? Theme.alpha(Theme.onAccent, 0.30) : Theme.inkFaint
            }
        }
        Column {
            id: heroCol
            anchors.left: heroDisc.right
            anchors.leftMargin: Theme.s3
            anchors.right: heroChip.visible ? heroChip.left : parent.right
            // the words swap when the live network changes (connected, dropped, switched):
            // a dip and fade back so the change reads as a change, not a flicker
            Connections { target: wifiSheet; function onLiveChanged() { heroSwap.restart(); } }
            NumberAnimation { id: heroSwap; target: heroCol; property: "opacity"; from: 0.25; to: 1; duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
            anchors.rightMargin: Theme.s3
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            StyledText {
                width: parent.width; elide: Text.ElideRight
                variant: "body"; font.weight: Theme.wMedium
                text: !Network.wifiAvailable ? "No Wi-Fi"
                    : !wifiSheet.on ? "Wi-Fi is off" : wifiSheet.live ? wifiSheet.live.name : "Not connected"
                color: Theme.inkPrimary
            }
            StyledText {
                width: parent.width; elide: Text.ElideRight
                variant: "caption"
                text: !Network.wifiAvailable ? (Network.managed ? "NetworkManager has no Wi-Fi device" : "Networking isn't run by NetworkManager here")
                    : !wifiSheet.on ? "Turn it on to see networks"
                    : wifiSheet.live ? ((wifiSheet.live.stateChanging ? "Connecting" : "Connected") + "  ·  " + wifiSheet.secLabel(wifiSheet.live) + "  ·  " + Math.round(wifiSheet.live.signalStrength * 100) + "% signal")
                    : "Pick a network below"
                color: Theme.inkDim
            }
        }
        CcSheetBits.Chip { tint: Theme.hue("toggles");
            id: heroChip
            anchors.right: parent.right
            anchors.rightMargin: Theme.s3
            anchors.verticalCenter: parent.verticalCenter
            visible: wifiSheet.on && !!wifiSheet.live
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
            text: "Disconnect"
            onClicked: if (wifiSheet.live) wifiSheet.live.disconnect()
        }
    }

    // ── the rest ────────────────────────────────────────────────────────────────────
    CcSheetBits.SectionLabel {
        visible: wifiSheet.on
        text: "Networks"
        busy: wifiSheet.scanning
        opacity: visible ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
    }

    ListView {
        id: list
        visible: wifiSheet.on
        width: parent.width
        height: Math.min(contentHeight, 320)
        clip: true
        spacing: Theme.s1
        // ScriptModel, not the bare array: the service republishes the (equal) list on every
        // scan tick, and a plain array model would rebuild every row each time, dropping the
        // inline password field mid-typing. ScriptModel diffs by object identity.
        model: ScriptModel { values: Network.wifiNetworks }
        boundsBehavior: Flickable.StopAtBounds
        // networks found fade in (the row owns that) and the rest spring into place (a scan
        // re-sorting by signal is a move, and reads as one). No `remove` fade: a delegate
        // kept alive for it outlives its network object and every binding on it reads null.
        displaced: CcSheetBits.MoveSpring {}
        move: CcSheetBits.MoveSpring {}

        delegate: Item {
            id: row
            required property var modelData
            readonly property var net: modelData
            required property int index
            readonly property bool isLive: net.connected
            readonly property bool expanded: wifiSheet.panel && wifiSheet.panel.pskTarget === net
            // rank among the listed (non-live) networks; beyond shownMax it is folded away
            readonly property int rank: index - (wifiSheet.liveIndex >= 0 && wifiSheet.liveIndex < index ? 1 : 0)
            readonly property bool folded: !wifiSheet.showAll && rank >= wifiSheet.shownMax
            width: ListView.view.width
            // the live network sits in the hero, not in the list
            height: (isLive || folded) ? 0 : (expanded ? 44 + 44 + Theme.s2 : 44)
            // follow the animated height, never the state: the row was blinking out the
            // instant it connected while its height still had a spring to run
            visible: height > 0.5
            opacity: entered * Math.min(1, height / 44)
            // delegate-owned entrance (patterns.md #5): a positioner `add` transition is cancelled
            // by the next relayout and strands the row at opacity 0
            property real entered: 0
            Component.onCompleted: entered = 1
            Behavior on entered { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
            Behavior on height { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
            clip: true

            Rectangle {
                anchors.fill: parent
                radius: Theme.rSm + 2
                color: rowMa.containsMouse || row.expanded ? Theme.selection : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
            }
            MouseArea {
                id: rowMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: m => { if (m.button === Qt.RightButton) wifiSheet.menuFor(row.net, row, m.x, m.y); else wifiSheet.press(row.net); }
            }

            CcSheetBits.Disc { tint: Theme.hue("toggles");
                id: rowDisc
                x: Theme.s2; y: (44 - height) / 2
                size: 32
                WifiIcon {
                    anchors.centerIn: parent
                    active: true
                    strength: row.net.signalStrength
                    color: Theme.inkPrimary
                    dimColor: Theme.inkFaint
                }
            }
            Column {
                anchors.left: rowDisc.right
                anchors.leftMargin: Theme.s3
                anchors.right: rowRight.left
                anchors.rightMargin: Theme.s2
                y: 22 - height / 2
                spacing: 1
                StyledText {
                    width: parent.width; elide: Text.ElideRight
                    variant: "label"; font.weight: Theme.wMedium
                    text: (row.net.name && row.net.name !== "") ? row.net.name : "(hidden network)"
                    color: Theme.inkPrimary
                }
                StyledText {
                    width: parent.width; elide: Text.ElideRight
                    variant: "caption"
                    text: row.net.stateChanging ? "Connecting…" : (wifiSheet.secLabel(row.net) + (row.net.known ? "  ·  Saved" : ""))
                    color: row.net.stateChanging ? Theme.hue("toggles") : Theme.inkDim
                }
            }
            // the lock is pinned to the row's edge so every row's lock lines up; the hover
            // verb hangs off it to the left (a Row let the wider "Connect" shove saved rows'
            // locks out of line even at opacity 0)
            Item {
                id: rowRight
                anchors.right: parent.right
                anchors.rightMargin: Theme.s3
                y: 0; height: 44
                width: lock.width + verb.implicitWidth + Theme.s2
                Icon { id: lock; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; visible: wifiSheet.secured(row.net); name: "lock"; size: 14; color: Theme.inkFaint; opacity: visible ? 1 : 0 }
                StyledText {
                    id: verb
                    anchors.right: lock.visible ? lock.left : parent.right
                    anchors.rightMargin: lock.visible ? Theme.s2 : 0
                    capCentreIn: parent
                    variant: "caption"; font.weight: Theme.wMedium
                    text: row.net.known ? "Connect" : "Join"
                    color: Theme.hue("toggles")
                    opacity: rowMa.containsMouse ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }
                }
            }

            // inline password entry (unknown + secured)
            Item {
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: Theme.s2; anchors.rightMargin: Theme.s2
                y: 44
                height: 44
                opacity: row.expanded ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }
                Rectangle {
                    anchors.fill: parent
                    anchors.bottomMargin: Theme.s2
                    radius: Theme.rSm
                    color: Theme.sunken
                    TextInput {
                        id: psk
                        anchors.left: parent.left; anchors.right: go.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.s3; anchors.rightMargin: Theme.s2
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        color: Theme.inkPrimary
                        font.family: Theme.fontBody
                        font.pixelSize: Theme.fsLabel
                        clip: true
                        enabled: row.expanded
                        onEnabledChanged: if (enabled) Qt.callLater(() => psk.forceActiveFocus())
                        Keys.onEscapePressed: wifiSheet.panel.pskTarget = null
                        Keys.onReturnPressed: go.clicked()
                        Keys.onEnterPressed: go.clicked()
                        StyledText { anchors.verticalCenter: parent.verticalCenter; visible: psk.text === ""; variant: "label"; text: "Password"; color: Theme.inkFaint }
                    }
                    CcSheetBits.Chip { tint: Theme.hue("toggles");
                        id: go
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Join"
                        accent: true
                        enabledLook: psk.text.length > 0
                        onClicked: {
                            if (psk.text.length === 0) return;
                            row.net.connectWithPsk(psk.text);
                            psk.text = "";
                            wifiSheet.panel.pskTarget = null;
                        }
                    }
                }
            }
        }
    }

    // the fold: how many more there are, and the way to see them
    Item {
        visible: wifiSheet.on && wifiSheet.hidden > 0
        width: parent.width
        height: 32
        opacity: visible ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
        CcSheetBits.Chip { tint: Theme.hue("toggles");
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            text: wifiSheet.showAll ? "Show fewer" : ("See all  ·  " + wifiSheet.hidden + " more")
            onClicked: wifiSheet.showAll = !wifiSheet.showAll
        }
    }

    StyledText {
        visible: wifiSheet.on && Network.wifiNetworks.length === 0
        variant: "label"; text: "Looking for networks…"; color: Theme.inkDim
        opacity: visible ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
    }
}
