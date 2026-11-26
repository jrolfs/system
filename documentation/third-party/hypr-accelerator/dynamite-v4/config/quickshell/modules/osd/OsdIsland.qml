import QtQuick
import "../../theme"
import "../../services"
import "../../components"
import "../../config"

// OSD content that lives INSIDE the bar island. Bump the volume or brightness and the
// island morphs into this compact level pill, then snaps back (see Bar.qml; it's a notch
// state, same idea as the notification). Flat: a custom icon, an accent level bar, a
// tabular %. The accent only marks the value here, nothing else. OsdState drives all of it.
Item {
    id: root

    implicitHeight: 24

    readonly property bool muted: OsdState.kind === "volume" && OsdState.muted
    readonly property real frac: Math.max(0, Math.min(1, OsdState.value / 100))

    // Snap the fill into place on first appearance (while the island's still morphing
    // open), then animate value changes once it's open. Skip this and the fill crawls up
    // from 0 on every single open (that ugly "jump"); animating mid-morph just looks laggy.
    property bool settled: false
    Connections {
        target: OsdState
        function onActiveChanged() {
            if (OsdState.active) settleTimer.restart();
            else { root.settled = false; settleTimer.stop(); }
        }
    }
    Timer { id: settleTimer; interval: Theme.dSpring; onTriggered: root.settled = true }

    // The kind icon, level-reactive and animated: waves grow with volume, rays brighten
    // with brightness. Two components share the left slot, only the active one shows.
    readonly property bool isMode: OsdState.kind === "mode"
    readonly property real modeWidth: modeRow.implicitWidth   // so the pill can size to the label

    // generic toggle-mode indicator: a ringed icon + label, centred
    Row {
        id: modeRow
        anchors.centerIn: parent
        spacing: Theme.s2
        visible: root.isMode
        ModeIcon {
            anchors.verticalCenter: parent.verticalCenter
            icon: OsdState.modeIcon
            on: OsdState.modeOn
            size: 18
        }
        StyledText {
            capCentreIn: parent
            variant: "label"
            font.weight: Theme.wMedium
            text: OsdState.modeLabel
            color: Theme.inkPrimary
        }
    }

    // level pill (volume / brightness)
    Item {
        id: glyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.iconSize
        height: Theme.iconSize
        visible: !root.isMode
        VolumeIcon {
            anchors.centerIn: parent
            visible: OsdState.kind !== "brightness"
            level: root.frac
            muted: root.muted
            color: root.muted ? Theme.inkDim : Theme.inkPrimary
        }
        BrightnessIcon {
            anchors.centerIn: parent
            visible: OsdState.kind === "brightness"
            level: root.frac
            color: Theme.inkPrimary
        }
    }

    // value readout, tabular figures so the width never twitches as it ticks
    StyledText {
        id: pct
        anchors.right: parent.right
        capCentreIn: parent
        width: 38
        horizontalAlignment: Text.AlignRight
        variant: "caption"
        font.features: { "tnum": 1 }
        visible: !root.isMode
        text: `${OsdState.value}%`
        color: Theme.inkDim
    }

    // flat accent level bar (non-interactive)
    Rectangle {
        id: track
        visible: !root.isMode
        anchors.left: glyph.right
        anchors.right: pct.left
        anchors.leftMargin: Theme.s3
        anchors.rightMargin: Theme.s3
        anchors.verticalCenter: parent.verticalCenter
        height: Config.osdBarHeight
        radius: height / 2
        color: Theme.fillHigh

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(parent.height, parent.width * root.frac)   // floor it so 0% is still a rounded dot
            radius: parent.radius
            color: root.muted ? Theme.inkDim : Theme.accent
            // animate value changes once settled; snap during the open (see `settled`)
            Behavior on width { enabled: root.settled; NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
            Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
        }
    }
}
