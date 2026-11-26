import QtQuick
import "../../theme"
import "../../config"
import "../../services"
import "../../components"

// Display (brightness) and Sound (volume) at any supported size. The footprint decides
// the FORM, the way iOS and One UI 8.5 flip a slider's orientation by size:
//
//     3 x 1          bare track with the symbol in it
//     4..full x 1    Tahoe's slider card: title row, track underneath
//     1..2 x 2       iOS's tall vertical slider, symbol at the foot
//     3..full x 2    tall card: title, percentage readout, a fatter track
//
// The symbol in the track is a press target of its own: on Sound it mutes, on Display it
// opens the display sub-view. Both cards carry the same plain chevron at the top right of
// the title row (Display -> display sub-view, Sound -> audio devices); at sizes with no
// title row the symbol press is the way in.
Item {
    id: tile

    property var ctl: null
    readonly property color tone: Theme.hue("sliders")
    readonly property string key: ctl ? ctl.key : ""
    readonly property int w: ctl ? ctl.w : 1
    readonly property int h: ctl ? ctl.h : 1
    readonly property bool interactive: ctl ? ctl.interactive : true

    readonly property bool isSound: key === "sound"
    readonly property var mon: Brightness.focused()
    readonly property real from: 0
    readonly property real to: isSound ? 1 : 100
    readonly property real value: isSound ? Audio.volume : (mon ? mon.percentage : 0)
    readonly property real ratio: to === from ? 0 : Math.max(0, Math.min(1, (value - from) / (to - from)))
    readonly property bool dim: isSound && Audio.muted
    readonly property string icon: isSound ? (Audio.muted ? "volumeMuted" : "volume") : "brightness"
    readonly property string label: isSound ? "Sound" : "Display"
    // No brightness to drive on the focused display (a TV over HDMI: no backlight, and
    // DDC/CI rarely gets through), so a slider would sit at zero and move nothing. The
    // tile becomes a plain Display card instead: what the screen is running at, and a
    // press opens the display sheet for scale, mode and night light.
    readonly property bool summary: !isSound && !(mon && mon.ready)
    function openSheet() {
        if (!ctl) return;
        ctl.origin = tile.mapToItem(null, 0, 0, tile.width, tile.height);
        ctl.originKind = "tile";
        ctl.originRadius = Theme.rXl;
        ctl.originTint = "transparent";
        ctl.originRest = "transparent";
        ctl.menu("display");
    }

    function set(r) {
        r = Math.max(0, Math.min(1, r));
        const v = from + r * (to - from);
        if (isSound) Audio.setVolume(v);
        else if (mon) mon.setBrightness(v);
    }

    // While the POINTER owns the value (a drag, and the moment after a click or drag), the
    // fill follows the pointer, not the backend. Volume comes back from PipeWire a beat
    // after every setVolume and brightness only on the next poll (up to two seconds), and
    // a fill bound to those echoes mid-drag rubber-banded between where the finger was and
    // where the hardware still said it was. The hold hands back to the backend as soon as
    // it catches up (within 1.5%), or after a grace period if it never does (a brightness
    // write that silently failed should end up showing the truth).
    property real localRatio: -1
    readonly property real shown: localRatio >= 0 ? localRatio : ratio
    onRatioChanged: if (localRatio >= 0 && !hMa.dragging && !vMa.dragging && Math.abs(ratio - localRatio) < 0.015) localRatio = -1
    Timer { id: holdTimer; interval: 1600; onTriggered: tile.localRatio = -1 }
    function own(r) {
        r = Math.max(0, Math.min(1, r));
        localRatio = r;
        holdTimer.restart();
        set(r);
    }
    function iconPress() {
        if (isSound) Audio.toggleMute();
        else if (ctl) { ctl.origin = (vertical ? vIcon : hIcon).mapToItem(null, 0, 0, trackIcon, trackIcon); ctl.originKind = "disc"; ctl.originRadius = tile.trackIcon / 2; ctl.originTint = "transparent"; ctl.originRest = "transparent"; ctl.menu("display"); }
    }

    readonly property bool vertical: h >= 2 && w <= 2
    readonly property bool tall: h >= 2 && w >= 3
    readonly property color fillColor: dim ? Theme.alpha(tile.tone, 0.35) : tile.tone

    // ── metrics ──
    // All of these used to be fixed, so at 5 columns the title and the track sat 36px apart
    // and at 9 they overlapped. They come off the cell now (CcControl.k); at the default
    // 7-column cell they are exactly the old numbers: 8 above the title, 6 under it, a 26px
    // track in a card, 34 bare. The title row only appears where the box can carry one AND
    // still leave a usable track. Below that the card falls back to the bare-track form,
    // the same way it already does at three cells wide.
    readonly property real k: ctl ? ctl.k : 1
    readonly property real hpad: ctl ? ctl.pad : 12
    readonly property real vpad: tile.tall ? hpad : Math.round(Math.max(5, Math.min(12, 8 * k)))
    readonly property real headH: tile.tall ? 20 : 16
    readonly property real headGap: Math.round(Math.max(4, Math.min(10, 6 * k)))
    readonly property real minTrack: 22
    readonly property bool fitsLabel: height >= vpad * 2 + headH + headGap + minTrack
    readonly property bool hasLabel: tall || (h === 1 && w >= 4 && fitsLabel)
    // the track takes whatever the title leaves, so there is never a pocket of dead air
    // between the two; bare, it keeps its share of the box and centres
    readonly property real trackH: hasLabel ? Math.max(minTrack, height - vpad * 2 - headH - headGap)
                                            : Math.round(Math.max(18, Math.min(44, height * 0.53)))
    readonly property real trackIcon: Math.round(Math.max(12, Math.min(26, trackH * 0.69)))
    readonly property real chevD: Math.round(Math.max(20, Math.min(34, 26 * k)))
    readonly property real chevG: Math.round(Math.max(11, Math.min(18, 14 * k)))

    Rectangle {
        anchors.fill: parent
        radius: Theme.rXl
        color: Theme.surfaceOverlay
    }


    // the glass rim, drawn ON TOP so the hover veil never softens it
    Rectangle {
        anchors.fill: parent
        radius: Theme.rXl
        color: "transparent"
        border.width: 1
        border.color: Theme.rim
        z: 5
    }

    // ── title row (cards only) ──
    Item {
        id: head
        visible: tile.hasLabel && !tile.summary
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: tile.vpad; leftMargin: tile.hpad + 4; rightMargin: tile.hpad }
        height: tile.headH
        StyledText {
            anchors.left: parent.left
            capCentreIn: parent
            variant: "label"
            font.weight: Theme.wMedium
            text: tile.label
            color: Theme.inkPrimary
        }
        StyledText {
            visible: tile.tall
            anchors.right: chevron.left
            anchors.rightMargin: Theme.s2
            capCentreIn: parent
            variant: "caption"
            text: Math.round(tile.shown * 100) + "%"
            color: Theme.inkDim
        }
        // The button: a disc with the chevron on it. The disc is what MORPHS into the card
        // (the sheet starts as this exact circle), so both are lent to the sheet while that
        // is live; the sheet's own spring brings them back with the bounce.
        Rectangle {
            id: chevDisc
            anchors.centerIn: chevron
            width: tile.chevD; height: tile.chevD; radius: tile.chevD / 2
            color: headMa.containsMouse ? Theme.fillHigh : Theme.fillLow
            Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
            opacity: tile.ctl && tile.ctl.chevronLent ? 0 : 1
        }
        Icon {
            id: chevron
            anchors.right: parent.right
            anchors.rightMargin: Math.round(tile.chevD * 0.23)
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron"
            size: tile.chevG
            color: headMa.containsMouse ? tile.tone : Theme.inkDim
            Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
            // instant, like the disc: the sheet's copy is on the same pixels at the same
            // opacity at the moment of hand-off, in both directions
            opacity: tile.ctl && tile.ctl.chevronLent ? 0 : 1
        }
        MouseArea {
            id: headMa
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            enabled: tile.interactive
            cursorShape: Qt.PointingHandCursor
            onClicked: if (tile.ctl) { tile.ctl.origin = chevDisc.mapToItem(null, 0, 0, chevDisc.width, chevDisc.height); tile.ctl.originKind = "disc"; tile.ctl.originRadius = chevDisc.width / 2; tile.ctl.originTint = Theme.fillHigh; tile.ctl.originRest = Theme.fillLow; tile.ctl.menu(tile.isSound ? "audio" : "display"); }
        }
    }

    // ── horizontal track ──
    Item {
        id: track
        visible: !tile.vertical && !tile.summary
        anchors.left: parent.left
        anchors.leftMargin: tile.hpad
        anchors.right: parent.right
        anchors.rightMargin: tile.hpad
        // Positioned by y, NOT by switching anchors with `undefined`: a binding that flips
        // an anchor line to undefined does not reliably unset it once it has been set, so a
        // tile that changed form ended up with bottom AND verticalCenter both active and the
        // track stretched between them. Plain arithmetic has no such memory.
        // One-row card budget: 8 + 16 title + 26 track + 8 = the cell, with room to spare.
        height: tile.trackH
        y: tile.hasLabel ? tile.vpad + tile.headH + tile.headGap : (parent.height - height) / 2

        Rectangle {
            anchors.fill: parent
            radius: Theme.rPill
            color: Theme.sunken
            Rectangle {
                id: hFill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(height, parent.width * tile.shown)   // keep the cap round when low
                radius: Theme.rPill
                color: tile.fillColor
                opacity: tile.shown > 0 ? 1 : 0
                // Glide to values that arrive from OUTSIDE (volume and brightness keys, a
                // pactl from a terminal) AND to a plain click on the track. Off only once the
                // pointer actually MOVES with the button down: a drag has to stick to the
                // finger, and an eased lag there reads as the slider fighting you. Gating on
                // `pressed` was wrong, it made a tap-to-position jump instead of glide.
                Behavior on width   { enabled: !hMa.dragging; NumberAnimation { duration: Theme.dur(Theme.dBase); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }
                Behavior on color   { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
            }
        }
        Icon {
            id: hIcon
            anchors.left: parent.left
            anchors.leftMargin: tile.hpad
            anchors.verticalCenter: parent.verticalCenter
            name: tile.icon
            size: tile.trackIcon
            // flips as the ANIMATED fill edge actually crosses it, not when the value does
            color: hFill.width > tile.hpad + tile.trackIcon && !tile.dim ? Theme.onAccent : Theme.inkPrimary
            Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
        }
        MouseArea {
            id: hMa
            anchors.fill: parent
            enabled: tile.interactive
            cursorShape: Qt.PointingHandCursor
            property bool iconPress: false
            property bool dragging: false      // true once the pointer has moved under the button
            property real pressX: 0
            onPressed: m => { iconPress = m.x < tile.hpad + tile.trackIcon + 8; dragging = false; pressX = m.x; if (!iconPress) tile.own(m.x / width); }
            onPositionChanged: m => {
                if (!pressed || iconPress) return;
                if (!dragging && Math.abs(m.x - pressX) < 3) return;   // a still finger is a click, not a drag
                dragging = true;
                tile.own(m.x / width);
            }
            onReleased: { dragging = false; holdTimer.restart(); }
            onCanceled: { dragging = false; holdTimer.restart(); }
            onClicked: { if (iconPress) tile.iconPress(); }
        }
    }

    // ── vertical track (the iOS tall slider) ──
    Item {
        id: vtrack
        visible: tile.vertical && !tile.summary
        width: Math.min(parent.width - tile.vpad * 2, Math.round(48 * tile.k))
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: tile.vpad
        anchors.bottomMargin: tile.vpad

        Rectangle {
            anchors.fill: parent
            radius: Theme.rPill
            color: Theme.sunken
            Rectangle {
                id: vFill
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.max(width, parent.height * tile.shown)
                radius: Theme.rPill
                color: tile.fillColor
                opacity: tile.shown > 0 ? 1 : 0
                Behavior on height  { enabled: !vMa.dragging; NumberAnimation { duration: Theme.dur(Theme.dBase); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }
                Behavior on color   { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
            }
        }
        Icon {
            id: vIcon
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: tile.hpad
            name: tile.icon
            size: tile.trackIcon
            color: vFill.height > tile.hpad + tile.trackIcon && !tile.dim ? Theme.onAccent : Theme.inkPrimary
            Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
        }
        MouseArea {
            id: vMa
            anchors.fill: parent
            enabled: tile.interactive
            cursorShape: Qt.PointingHandCursor
            property bool iconPress: false
            property bool dragging: false
            property real pressY: 0
            onPressed: m => { iconPress = m.y > height - (tile.hpad + tile.trackIcon + 8); dragging = false; pressY = m.y; if (!iconPress) tile.own(1 - m.y / height); }
            onPositionChanged: m => {
                if (!pressed || iconPress) return;
                if (!dragging && Math.abs(m.y - pressY) < 3) return;
                dragging = true;
                tile.own(1 - m.y / height);
            }
            onReleased: { dragging = false; holdTimer.restart(); }
            onCanceled: { dragging = false; holdTimer.restart(); }
            onClicked: { if (iconPress) tile.iconPress(); }
        }
    }

    // ── summary form (Display with no brightness control) ──
    Item {
        id: summaryBox
        visible: tile.summary
        anchors.fill: parent
        readonly property real disc: tile.ctl ? tile.ctl.discSize : 44
        readonly property bool stacked: tile.h >= 2
        readonly property var cur: Display.current

        Rectangle {
            anchors.fill: parent
            radius: Theme.rXl
            color: Theme.fillLow
            opacity: sumMa.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }
        }
        Rectangle {
            id: sumDisc
            width: summaryBox.disc; height: width; radius: width / 2
            x: summaryBox.stacked ? tile.hpad : Math.max(4, Math.round((Math.min(tile.height, tile.ctl ? tile.ctl.cell : 64) - width) / 2))
            y: summaryBox.stacked ? tile.hpad : (parent.height - height) / 2
            color: Theme.fillHigh
            Icon { anchors.centerIn: parent; name: "display"; size: tile.ctl ? tile.ctl.glyph : Theme.iconSize; color: Theme.inkPrimary }
        }
        Column {
            visible: tile.w >= 2
            x: summaryBox.stacked ? tile.hpad : sumDisc.x + sumDisc.width + tile.hpad
            width: parent.width - x - tile.hpad
            y: summaryBox.stacked ? parent.height - height - tile.hpad : (parent.height - height) / 2
            spacing: 1
            StyledText { width: parent.width; elide: Text.ElideRight; variant: "body"; font.weight: Theme.wMedium; text: "Display"; color: Theme.inkPrimary }
            StyledText {
                width: parent.width
                elide: Text.ElideRight
                variant: "caption"
                visible: text !== ""
                text: summaryBox.cur ? summaryBox.cur.width + "×" + summaryBox.cur.height + "  ·  " + Display.fmtScale(summaryBox.cur.scale) + "×" : ""
                color: Theme.inkDim
            }
        }
        MouseArea {
            id: sumMa
            anchors.fill: parent
            hoverEnabled: true
            enabled: tile.interactive
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.openSheet()
        }
    }
}
