import QtQuick
import QtQuick.Shapes
import "../../theme"
import "../../config"
import "../../services"
import "../../components"

// One toggle (or the lock, a one-shot action) at any of the sizes it supports:
//
//     1x1         circle, symbol only (Tahoe's round buttons; iOS's small size)
//     w x 1, w>1  capsule: state circle + title, plus the value line from 3 wide
//     w x 2       square card: state circle up top, title + value along the bottom
//
// That is the platforms' shared size vocabulary: a bigger footprint SHOWS more (symbol,
// then title, then value), it doesn't just stretch. The tile body stays a quiet surface
// in every state; the ICON-CIRCLE carries on/off (the whole tile is the circle at 1x1).
// Circle press always toggles; body press opens the sub-view on controls that have one
// (Wi-Fi, Bluetooth), else toggles too, which is Android 16's dual-target tile.
Item {
    id: tile

    property var ctl: null
    readonly property color tone: Theme.hue("toggles")
    readonly property string key: ctl ? ctl.key : ""
    readonly property int w: ctl ? ctl.w : 1
    readonly property int h: ctl ? ctl.h : 1
    readonly property bool interactive: ctl ? ctl.interactive : true

    readonly property var reg: Config.ccReg(key)
    // The hardware behind this control is missing: no Wi-Fi radio (or no NetworkManager to
    // drive one), no Bluetooth adapter, no hyprsunset. The tile stays in the layout but
    // goes inert and says why, rather than toggling a state that changes nothing.
    readonly property bool unavailable: key === "wifi" ? !Network.wifiAvailable
                                      : key === "bluetooth" ? !Bluetooth.available
                                      : key === "nightlight" ? !NightLight.available
                                      : false
    // Without Wi-Fi the Wi-Fi tile becomes a read-only network status, so a wired machine
    // still sees that it's online in the place it would look.
    readonly property bool wiredStatus: key === "wifi" && unavailable
    readonly property bool active: interactive && !unavailable
    readonly property string label: wiredStatus ? (Network.isWired ? "Ethernet" : "Network") : (reg ? reg.label : "")
    readonly property string icon: reg ? reg.icon : ""
    readonly property bool hasMenu: key === "wifi" || key === "bluetooth"
    readonly property bool on: key === "wifi" ? (wiredStatus ? Network.connected : Network.wifiEnabled)
                             : key === "bluetooth" ? Bluetooth.enabled
                             : key === "focus" ? GlobalState.dnd
                             : key === "nightlight" ? NightLight.enabled
                             : key === "gamemode" ? GameMode.enabled
                             : false
    readonly property string sublabel: wiredStatus ? (Network.connected ? "Connected" : "Offline")
                                     : unavailable ? (key === "bluetooth" ? "No adapter" : "Unavailable")
                                     : key === "wifi" ? (Network.wifiEnabled ? Network.label : "Off")
                                     : key === "bluetooth" ? (Bluetooth.enabled ? (Bluetooth.hasConnection ? Bluetooth.label : "On") : "Off")
                                     : key === "lock" ? "Screen"
                                     : (on ? "On" : "Off")

    function toggle() {
        if (unavailable) return;
        if (key === "wifi") Network.toggleWifi();
        else if (key === "bluetooth") Bluetooth.toggle();
        else if (key === "focus") GlobalState.toggleDnd();
        else if (key === "nightlight") NightLight.toggle();
        else if (key === "gamemode") GameMode.toggle();
        else if (key === "lock" && ctl) ctl.lockRequested();
    }
    // the BODY opens the sub-view, so the body is what morphs into it: the sheet starts as
    // this tile's exact rect and corners, showing a live snapshot of it that cross-fades out
    function bodyPress() {
        if (unavailable) return;
        if (!(hasMenu && ctl)) { toggle(); return; }
        ctl.origin = tile.mapToItem(null, 0, 0, tile.width, tile.height);
        ctl.originKind = "tile";
        ctl.originRadius = bg.radius;
        ctl.originTint = "transparent";      // the snapshot carries the hover veil itself
        ctl.originRest = "transparent";
        ctl.menu(key);
    }

    readonly property bool circleOnly: w === 1 && h === 1
    readonly property bool card: h >= 2
    // the state circle and the insets come off the cell (CcControl), so the disc is not
    // lost in a 94px capsule at 5 columns nor jammed against the rim of a 47px one at 9
    readonly property real disc: ctl ? ctl.discSize : 44
    readonly property real inset: ctl ? ctl.discInset : 10
    readonly property real pad: ctl ? ctl.pad : 12
    readonly property real glyph: ctl ? ctl.glyph : Theme.iconSize
    readonly property bool hovered: active && (bodyMa.containsMouse || circleMa.containsMouse)

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: tile.circleOnly ? width / 2 : (tile.card ? Theme.rXl : height / 2)
        color: tile.circleOnly && tile.on ? tile.tone : Theme.surfaceOverlay
        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
    }
    Rectangle {   // hover veil, under the state circle so it never tints the state colour
        anchors.fill: parent
        radius: bg.radius
        color: Theme.fillLow
        opacity: tile.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }
    }
    MouseArea {
        id: bodyMa
        anchors.fill: parent
        hoverEnabled: true
        enabled: tile.active
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.circleOnly ? tile.toggle() : tile.bodyPress()
    }

    // 1x1: the tile IS the circle
    Icon {
        anchors.centerIn: parent
        visible: tile.circleOnly && tile.key !== "wifi"
        opacity: tile.unavailable ? 0.4 : 1
        name: tile.icon
        size: tile.glyph
        color: tile.on ? Theme.onAccent : Theme.inkPrimary
    }
    EthernetGlyph {
        anchors.centerIn: parent
        visible: tile.circleOnly && tile.wiredStatus
        size: tile.glyph
        color: tile.on ? Theme.onAccent : Theme.inkDim
    }
    WifiIcon {
        anchors.centerIn: parent
        visible: tile.circleOnly && tile.key === "wifi" && !tile.wiredStatus
        scale: tile.glyph / Theme.iconSize
        active: Network.connected
        strength: Network.connected ? (Network.isWifi ? Network.signalStrength : 1) : 0
        color: tile.on ? Theme.onAccent : Theme.inkPrimary
        dimColor: tile.on ? Theme.alpha(Theme.onAccent, 0.30) : Theme.inkFaint
    }


    // the glass rim, drawn ON TOP so the hover veil never softens it
    Rectangle {
        anchors.fill: parent
        radius: bg.radius
        color: "transparent"
        border.width: 1
        border.color: Theme.rim
        z: 5
    }

    // capsule / card: the state circle
    Rectangle {
        id: circle
        visible: !tile.circleOnly
        width: tile.disc; height: tile.disc; radius: tile.disc / 2
        x: tile.card ? tile.pad : tile.inset
        y: tile.card ? tile.pad : (parent.height - height) / 2
        color: tile.on ? tile.tone : Theme.fillHigh
        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
        Icon {
            anchors.centerIn: parent
            visible: tile.key !== "wifi"
            opacity: tile.unavailable ? 0.4 : 1
            name: tile.icon
            size: tile.glyph
            color: tile.on ? Theme.onAccent : Theme.inkPrimary
        }
        EthernetGlyph {
            anchors.centerIn: parent
            visible: tile.wiredStatus
            size: tile.glyph
            color: tile.on ? Theme.onAccent : Theme.inkDim
        }
        WifiIcon {
            anchors.centerIn: parent
            visible: tile.key === "wifi" && !tile.wiredStatus
            scale: tile.glyph / Theme.iconSize
            active: Network.connected
            strength: Network.connected ? (Network.isWifi ? Network.signalStrength : 1) : 0
            color: tile.on ? Theme.onAccent : Theme.inkPrimary
            dimColor: tile.on ? Theme.alpha(Theme.onAccent, 0.30) : Theme.inkFaint
        }
        MouseArea {
            id: circleMa
            anchors.fill: parent
            hoverEnabled: true
            enabled: tile.active
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.toggle()
        }
    }

    // capsule: beside the circle. card: along the bottom edge.
    Column {
        visible: !tile.circleOnly
        x: tile.card ? tile.pad : circle.x + circle.width + tile.pad
        width: parent.width - x - tile.pad
        // y, not anchors toggled with undefined (see CcSliderTile for why)
        y: tile.card ? parent.height - height - tile.pad : (parent.height - height) / 2
        spacing: 1
        StyledText {
            width: parent.width
            elide: Text.ElideRight
            variant: "body"
            font.weight: Theme.wMedium
            text: tile.label
            color: tile.unavailable && !tile.wiredStatus ? Theme.inkDim : Theme.inkPrimary
        }
        StyledText {
            width: parent.width
            elide: Text.ElideRight
            variant: "caption"
            visible: (tile.w >= 3 || tile.card) && text !== ""
            text: tile.sublabel
            color: Theme.inkDim
        }
    }

    // A wired connection, as a little network tree. Icon has no such glyph, and the Wi-Fi
    // fan at full strength would claim a radio this machine doesn't have.
    component EthernetGlyph: Shape {
        id: eg
        property real size: Theme.iconSize
        property color color: Theme.inkPrimary
        width: size
        height: size
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { xScale: eg.size / 24; yScale: eg.size / 24 }
        ShapePath {
            fillColor: "transparent"
            strokeColor: eg.color
            strokeWidth: Math.max(Theme.iconStroke, 1.2 * 24 / Math.max(1, eg.size))
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M9,3.5 H15 V9 H9 Z M12,9 V12.5 M6,15 V12.5 H18 V15 M3.5,15 H8.5 V20.5 H3.5 Z M15.5,15 H20.5 V20.5 H15.5 Z" }
        }
    }
}
