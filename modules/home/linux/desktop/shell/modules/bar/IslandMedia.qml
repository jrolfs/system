import QtQuick
import QtQuick.Effects
import Quickshell.Services.Mpris
import "../../config"
import "../../theme"
import "../../services"
import "../../components"

// The media card under the expanded island's clock: album art on the left, the title
// and the artist left-aligned beside it, and a visualizer on the right that moves with
// the audio (cava's FFT, see services/Cava.qml). It is a CARD, not more ink on the
// island: one elevation step up, a hairline rim and the floating-surface shadow, so it
// sits on the island instead of blending into it. Click it to play or pause; scroll over
// it to change track.
Item {
    id: root

    property real cardW: 300
    property real cardH: 58
    property bool live: false         // on screen; gates the FFT and the art crossfades
    readonly property var p: Media.player
    readonly property bool playing: p ? p.isPlaying : false
    readonly property color tone: Theme.hue("media")

    implicitWidth: cardW
    implicitHeight: cardH
    width: implicitWidth
    height: implicitHeight

    // ask for levels only while on screen (the service runs cava only while something
    // plays as well)
    property bool asked: false
    onLiveChanged: { if (live && !asked) { Cava.demand++; asked = true; } else if (!live && asked) { Cava.demand--; asked = false; } }
    Component.onDestruction: if (asked) Cava.demand--

    // ── the surface ──
    Rectangle {
        id: card
        anchors.fill: parent
        radius: Theme.rLg
        color: Theme.surfacePanel
        border.width: 1
        border.color: Theme.rim
        layer.enabled: Theme.shadows
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowBlur: Theme.shadowBlur
            shadowVerticalOffset: 3
            shadowOpacity: 1
            autoPaddingEnabled: true
        }
    }

    // ── art ──
    Item {
        id: artBox
        anchors.left: parent.left
        anchors.leftMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        width: root.cardH - 18; height: width
        Rectangle {
            anchors.fill: parent
            radius: Theme.rMd
            color: Theme.surfaceOverlay
            opacity: artImg.ready ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
            Icon { anchors.centerIn: parent; name: "music"; size: 16; color: root.tone }
        }
        Image {
            id: artImg
            readonly property bool ready: status === Image.Ready && source.toString() !== ""
            anchors.fill: parent
            source: root.p?.trackArtUrl ?? ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: false
            layer.enabled: true
        }
        Rectangle { id: artMask; anchors.fill: parent; radius: Theme.rMd; visible: false; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            source: artImg
            maskEnabled: true
            maskSource: artMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            opacity: artImg.ready ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
        }
    }

    // ── visualizer: cava's bands as thin rounded bars, grown from the centre line ──
    Row {
        id: viz
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        readonly property real maxH: root.cardH - 26
        readonly property real floor: 3
        Repeater {
            model: Cava.bars
            delegate: Item {
                required property int index
                width: 3
                height: viz.maxH
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: viz.floor + (viz.maxH - viz.floor) * (root.playing ? (Cava.levels[index] ?? 0) : 0)
                    radius: width / 2
                    color: root.playing ? root.tone : Theme.alpha(root.tone, 0.35)
                    // a short ease between cava's frames so the bars breathe instead of step
                    Behavior on height { NumberAnimation { duration: Theme.dur(70); easing.type: Easing.OutQuad } }
                    Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                }
            }
        }
    }

    // ── title and artist, left aligned, taking what is between the art and the bars ──
    Column {
        anchors.left: artBox.right
        anchors.leftMargin: 11
        anchors.right: viz.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        StyledText {
            width: parent.width
            text: root.p?.trackTitle ?? "Nothing playing"
            font.pixelSize: Theme.fsLabel
            font.weight: Theme.wSemiBold
            color: Theme.inkPrimary
            elide: Text.ElideRight
        }
        StyledText {
            width: parent.width
            visible: text !== ""
            text: root.p?.trackArtist ?? ""
            font.pixelSize: Theme.fsCaption
            color: Theme.inkDim
            elide: Text.ElideRight
        }
    }

    // ── press and scroll ──
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.p?.togglePlaying()
        onWheel: wheel => {
            const dy = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y;
            if (!Config.mediaScrollSwitch || dy === 0 || !root.p || cool.running) return;
            if (dy < 0 ? !root.p.canGoNext : !root.p.canGoPrevious) return;
            if (dy < 0) root.p.next(); else root.p.previous();
            cool.restart();
        }
    }
    Timer { id: cool; interval: 300 }
}
