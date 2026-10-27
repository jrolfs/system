import QtQuick
import QtQuick.Effects
import "../../theme"
import "../../config"
import "../../services"
import "../../components"

// Now Playing at any of its sizes, the size ladder iOS gives its Now Playing control:
//
//     1x1         play/pause circle (accent while playing)
//     2x1         mini capsule: play/pause + title
//     3..full x 1 strip: art thumb, title/artist, transport; progress line from 5 wide
//     w x 2       the card: blurred art as the backdrop, title/artist, transport, progress
//
// The card's art is blurred in one pass and masked in a second, because a single
// MultiEffect can't blur AND round: clip only clips the bounding rect.
Item {
    id: tile

    property var ctl: null
    readonly property color tone: Theme.hue("media")
    readonly property string key: ctl ? ctl.key : ""
    readonly property int w: ctl ? ctl.w : 1
    readonly property int h: ctl ? ctl.h : 1
    readonly property bool interactive: ctl ? ctl.interactive : true

    readonly property var p: Media.player
    readonly property bool playing: p ? p.isPlaying : false
    readonly property string title: p ? (p.trackTitle || "Unknown") : "Not playing"
    readonly property string artist: p ? (p.trackArtist || "") : ""
    readonly property string artUrl: p ? (p.trackArtUrl || "") : ""

    // same cell-derived metrics as the toggles: the mini capsule is the same shape
    readonly property real disc: ctl ? ctl.discSize : 44
    readonly property real inset: ctl ? ctl.discInset : 10
    readonly property real pad: ctl ? ctl.pad : 12
    readonly property real glyph: ctl ? ctl.glyph : Theme.iconSize

    readonly property bool circleOnly: w === 1 && h === 1
    readonly property bool mini: h === 1 && w === 2
    readonly property bool strip: h === 1 && w >= 3
    readonly property bool cardForm: h >= 2

    property real ratio: 0
    function refresh() { ratio = (p && p.length > 0) ? Math.max(0, Math.min(1, p.position / p.length)) : 0; }
    onPChanged: refresh()
    onVisibleChanged: refresh()
    Timer { interval: 1000; repeat: true; running: tile.visible && tile.playing; onTriggered: tile.refresh() }

    function togglePlay() { if (p && p.canTogglePlaying) p.togglePlaying(); }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: tile.circleOnly ? width / 2 : (tile.cardForm ? Theme.rXl : height / 2)
        color: tile.circleOnly && tile.playing ? tile.tone : Theme.surfaceOverlay
        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
    }

    // ── card backdrop: blur pass, then mask pass, then a veil of the shell base so the
    //    scheme's own ink stays readable over the art whichever way the scheme runs ──
    readonly property bool hasArt: tile.cardForm && mart.status === Image.Ready
    Image { id: mart; anchors.fill: parent; source: tile.cardForm ? tile.artUrl : ""; fillMode: Image.PreserveAspectCrop; cache: true; asynchronous: true; visible: false; layer.enabled: true }
    MultiEffect { id: martBlur; anchors.fill: parent; source: mart; blurEnabled: true; blur: 0.7; blurMax: 48; autoPaddingEnabled: false; visible: false; layer.enabled: true }
    Rectangle { id: martMask; anchors.fill: parent; radius: bg.radius; visible: false; layer.enabled: true }
    MultiEffect { anchors.fill: parent; source: martBlur; maskSource: martMask; maskEnabled: true; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0; visible: tile.hasArt }
    // the veil is TINTED with the scheme's accent, not a neutral wash: the art reads as
    // belonging to the theme rather than a photo pasted onto it. Base underneath keeps the
    // ink readable whichever way the scheme runs.
    Rectangle { anchors.fill: parent; radius: bg.radius; visible: tile.hasArt; color: Theme.alpha(Theme.mix(Theme.base, tile.tone, 0.32), 0.68) }


    // Hairline rim (Tahoe's glass edge, without the glass): a 1px stroke in the ink colour at
    // hairline alpha, drawn ON TOP so hover veils and album art never soften it. It is what
    // separates a tile from the black island without any glow.
    Rectangle {
        anchors.fill: parent
        radius: bg.radius
        color: "transparent"
        border.width: 1
        border.color: Theme.rim
        z: 5
    }

    Rectangle {   // hover veil for the two press-anywhere forms
        anchors.fill: parent
        radius: bg.radius
        color: Theme.fillLow
        opacity: tile.interactive && (tile.circleOnly || tile.mini) && wholeMa.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }
    }
    MouseArea {
        id: wholeMa
        anchors.fill: parent
        hoverEnabled: true
        enabled: tile.interactive && (tile.circleOnly || tile.mini)
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.togglePlay()
    }

    // ── 1x1 ──
    Icon {
        anchors.centerIn: parent
        visible: tile.circleOnly
        name: tile.playing ? "pause" : "play"
        size: tile.glyph
        color: tile.playing ? Theme.onAccent : Theme.inkPrimary
    }

    // ── 2x1 mini ──
    Rectangle {
        visible: tile.mini
        x: tile.inset
        anchors.verticalCenter: parent.verticalCenter
        width: tile.disc; height: tile.disc; radius: tile.disc / 2
        color: tile.playing ? tile.tone : Theme.fillHigh
        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
        Icon { anchors.centerIn: parent; name: tile.playing ? "pause" : "play"; size: tile.glyph; color: tile.playing ? Theme.onAccent : Theme.inkPrimary }
    }
    StyledText {
        visible: tile.mini
        x: tile.inset + tile.disc + tile.pad
        width: parent.width - x - tile.pad
        capCentreIn: parent
        elide: Text.ElideRight
        variant: "label"
        font.weight: Theme.wMedium
        text: tile.title
        color: Theme.inkPrimary
    }

    // ── strip ──
    Item {
        id: thumb
        visible: tile.strip
        anchors.left: parent.left
        anchors.leftMargin: Theme.s2
        anchors.verticalCenter: parent.verticalCenter
        width: parent.height - Theme.s2 * 2
        height: width
        Rectangle { anchors.fill: parent; radius: Theme.rMd; color: Theme.fillHigh
            Icon { anchors.centerIn: parent; name: "music"; color: Theme.inkDim; visible: !thumbFx.visible } }
        Image { id: thumbImg; anchors.fill: parent; source: tile.strip ? tile.artUrl : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; visible: false; layer.enabled: true; sourceSize.width: 96; sourceSize.height: 96 }
        Rectangle { id: thumbMask; anchors.fill: parent; radius: Theme.rMd; visible: false; layer.enabled: true }
        MultiEffect { id: thumbFx; anchors.fill: parent; source: thumbImg; maskSource: thumbMask; maskEnabled: true; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0; visible: tile.strip && thumbImg.status === Image.Ready }
    }
    Column {
        visible: tile.strip
        anchors.left: thumb.right
        anchors.leftMargin: Theme.s3
        anchors.right: stripTransport.left
        anchors.rightMargin: Theme.s3
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        StyledText { width: parent.width; elide: Text.ElideRight; variant: "label"; font.weight: Theme.wMedium; text: tile.title; color: Theme.inkPrimary }
        StyledText { width: parent.width; elide: Text.ElideRight; variant: "caption"; visible: text !== ""; text: tile.artist; color: Theme.inkDim }
        Rectangle {   // progress line, once there's width to spare
            visible: tile.w >= 5 && !!tile.p
            width: parent.width
            height: 3; radius: 1.5
            color: Theme.fillHigh
            Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: parent.width * tile.ratio; radius: 1.5; color: tile.tone }
        }
    }
    Row {
        id: stripTransport
        visible: tile.strip
        anchors.right: parent.right
        anchors.rightMargin: Theme.s3
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.s3
        Icon {
            visible: tile.w >= 4
            anchors.verticalCenter: parent.verticalCenter
            name: "prev"; color: Theme.inkPrimary
            opacity: tile.p && tile.p.canGoPrevious ? 1 : 0.35
            MouseArea { anchors.fill: parent; anchors.margins: -6; enabled: tile.interactive && tile.p && tile.p.canGoPrevious; cursorShape: Qt.PointingHandCursor; onClicked: tile.p.previous() }
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(Math.max(28, Math.min(48, 36 * (tile.ctl ? tile.ctl.k : 1)))); height: width; radius: width / 2
            color: tile.playing ? tile.tone : Theme.fillHigh
            Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
            Icon { anchors.centerIn: parent; name: tile.playing ? "pause" : "play"; size: Theme.iconSize - 2; color: tile.playing ? Theme.onAccent : Theme.inkPrimary }
            MouseArea { anchors.fill: parent; enabled: tile.interactive; cursorShape: Qt.PointingHandCursor; onClicked: tile.togglePlay() }
        }
        Icon {
            visible: tile.w >= 4
            anchors.verticalCenter: parent.verticalCenter
            name: "next"; color: Theme.inkPrimary
            opacity: tile.p && tile.p.canGoNext ? 1 : 0.35
            MouseArea { anchors.fill: parent; anchors.margins: -6; enabled: tile.interactive && tile.p && tile.p.canGoNext; cursorShape: Qt.PointingHandCursor; onClicked: tile.p.next() }
        }
    }

    // ── card ──
    Column {   // resting state, Tahoe's "Not Playing"
        anchors.centerIn: parent
        spacing: Theme.s2
        visible: tile.cardForm && !tile.p
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 40; height: 40; radius: 20
            color: Theme.fillHigh
            Icon { anchors.centerIn: parent; name: "music"; color: Theme.inkDim }
        }
        StyledText { anchors.horizontalCenter: parent.horizontalCenter; variant: "caption"; text: "Not playing"; color: Theme.inkDim }
    }
    Column {
        visible: tile.cardForm && !!tile.p
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Theme.s3; leftMargin: Theme.s4; rightMargin: Theme.s4 }
        spacing: 1
        StyledText { width: parent.width; elide: Text.ElideRight; variant: "label"; font.weight: Theme.wMedium; text: tile.title; color: Theme.inkPrimary }
        StyledText { width: parent.width; elide: Text.ElideRight; variant: "caption"; text: tile.artist; color: Theme.inkDim }
    }
    Row {
        visible: tile.cardForm && !!tile.p
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: cardProg.top
        anchors.bottomMargin: Theme.s3
        spacing: Theme.s4
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "prev"; color: Theme.inkPrimary
            opacity: tile.p && tile.p.canGoPrevious ? 1 : 0.35
            MouseArea { anchors.fill: parent; anchors.margins: -8; enabled: tile.interactive && tile.p && tile.p.canGoPrevious; cursorShape: Qt.PointingHandCursor; onClicked: tile.p.previous() }
        }
        Rectangle {
            width: 40; height: 40; radius: 20
            color: tile.tone
            Icon { anchors.centerIn: parent; name: tile.playing ? "pause" : "play"; color: Theme.onAccent }
            MouseArea { anchors.fill: parent; enabled: tile.interactive; cursorShape: Qt.PointingHandCursor; onClicked: tile.togglePlay() }
        }
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "next"; color: Theme.inkPrimary
            opacity: tile.p && tile.p.canGoNext ? 1 : 0.35
            MouseArea { anchors.fill: parent; anchors.margins: -8; enabled: tile.interactive && tile.p && tile.p.canGoNext; cursorShape: Qt.PointingHandCursor; onClicked: tile.p.next() }
        }
    }
    Rectangle {
        id: cardProg
        visible: tile.cardForm && !!tile.p
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: Theme.s4; rightMargin: Theme.s4; bottomMargin: Theme.s3 }
        height: 3; radius: 1.5
        color: Theme.fillHigh
        Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: parent.width * tile.ratio; radius: 1.5; color: tile.tone }
    }
}
