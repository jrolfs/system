import QtQuick
import Quickshell
import "../../theme"
import "../../config"
import "../../services"
import "../../components"

// The Display sheet: one card per monitor (name, resolution, refresh, a focused tag), each
// with its OWN brightness track (the laptop panel through the backlight, the Dell over
// DDC; both fade, see the Brightness service), the scale chips, and an inline resolution /
// refresh picker that folds out of the current mode. Then Night Light with its toggle and
// a warmth slider that re-applies live.
Column {
    id: displaySheet

    property var panel: null
    spacing: Theme.s3

    property string modesOpenFor: ""          // which monitor has its mode list unfolded
    property int folding: 0                   // mode lists mid-fold; the notch's height spring pauses while > 0
    onVisibleChanged: if (!visible) modesOpenFor = ""

    Repeater {
        model: Display.monitors
        delegate: Rectangle {
            id: card
            opacity: entered
            // delegate-owned entrance (patterns.md #5): a positioner `add` transition is cancelled
            // by the next relayout and strands the row at opacity 0
            property real entered: 0
            Component.onCompleted: entered = 1
            Behavior on entered { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
            required property var modelData
            readonly property var mon: modelData
            readonly property var ctl: Brightness.forName(mon.name)
            readonly property bool modesOpen: displaySheet.modesOpenFor === mon.name
            width: parent.width
            height: body.implicitHeight + Theme.s3 * 2
            radius: Theme.rLg
            color: Theme.surfaceBase
            border.width: 1
            border.color: Theme.rim
            clip: true

            Column {
                id: body
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.s3 }
                spacing: Theme.s2

                // header: name, geometry, focused
                Item {
                    width: parent.width
                    height: 36
                    CcSheetBits.Disc { tint: Theme.hue("sliders"); id: dDisc; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; size: 32; icon: "display"; live: card.mon.focused }
                    Column {
                        anchors.left: dDisc.right; anchors.leftMargin: Theme.s3
                        anchors.right: focusTag.left; anchors.rightMargin: Theme.s2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        StyledText { width: parent.width; elide: Text.ElideRight; variant: "label"; font.weight: Theme.wMedium; text: card.mon.name; color: Theme.inkPrimary }
                        StyledText { width: parent.width; elide: Text.ElideRight; variant: "caption"; text: card.mon.width + "×" + card.mon.height + (card.mon.hz ? "  ·  " + Math.round(card.mon.hz) + " Hz" : "") + "  ·  " + Display.fmtScale(card.mon.scale) + "×"; color: Theme.inkDim }
                    }
                    StyledText { id: focusTag; anchors.right: parent.right; capCentreIn: parent; visible: card.mon.focused; variant: "caption"; text: "focused"; color: Theme.hue("sliders") }
                }

                // brightness, per display, only where something can actually set it (a
                // backlight, or a monitor answering DDC/CI)
                CcSheetBits.Track { tint: Theme.hue("sliders");
                    visible: !!card.ctl && card.ctl.ready
                    icon: "brightness"
                    value: card.ctl ? card.ctl.percentage / 100 : 0
                    onMoved: v => { if (card.ctl) card.ctl.setBrightness(v * 100); }
                }

                // scale chips
                Flow {
                    width: parent.width
                    spacing: Theme.s1
                    Repeater {
                        model: Display.scalesFor(card.mon)
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool current: Math.abs(modelData - card.mon.scale) < 0.01
                            width: chipText.implicitWidth + Theme.s3 * 2
                            height: 30
                            radius: 15
                            color: current ? Theme.hue("sliders") : (chipMa.containsMouse ? Theme.fillHigh : Theme.fillLow)
                            opacity: Display.busy ? 0.5 : 1
                            Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                            StyledText { id: chipText; anchors.horizontalCenter: parent.horizontalCenter; capCentreIn: parent; variant: "caption"; font.weight: Theme.wMedium; text: Display.fmtScale(chip.modelData) + "×"; color: chip.current ? Theme.onAccent : Theme.inkPrimary }
                            MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !Display.busy && !chip.current; onClicked: Display.setScale(card.mon.name, chip.modelData) }
                        }
                    }
                }

                // resolution / refresh: the current mode, folding out the list
                Item {
                    width: parent.width
                    height: 32
                    Rectangle { anchors.fill: parent; radius: Theme.rSm; color: modeMa.containsMouse ? Theme.fillHigh : "transparent"; Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } } }
                    StyledText { anchors.left: parent.left; anchors.leftMargin: Theme.s2; capCentreIn: parent; variant: "caption"; text: "Resolution"; color: Theme.inkDim }
                    StyledText { anchors.right: modeChev.left; anchors.rightMargin: Theme.s2; capCentreIn: parent; variant: "caption"; font.weight: Theme.wMedium; text: card.mon.width + "×" + card.mon.height + (card.mon.hz ? " @ " + Math.round(card.mon.hz) + " Hz" : ""); color: Theme.inkPrimary }
                    Icon { id: modeChev; anchors.right: parent.right; anchors.rightMargin: Theme.s2; anchors.verticalCenter: parent.verticalCenter; name: "chevron"; size: 12; rotation: card.modesOpen ? 90 : 0; color: Theme.inkDim; Behavior on rotation { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } } }
                    MouseArea { id: modeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: displaySheet.modesOpenFor = card.modesOpen ? "" : card.mon.name }
                }
                // A monitor can advertise a dozen-plus modes; an uncapped Column ran the card
                // off the bottom of the screen. Capped to five rows here and scrolled.
                // Height comes from the row count (five rows max), never from contentHeight:
                // deriving it from contentHeight while animating fed back on itself (delegates
                // only exist once there's height to show them).
                // The fold is the ONE spring here: `fold` runs 0 -> 1 on the spring, the list
                // height follows it, the card and the sheet follow the list instantly, and the
                // island's own height spring is switched OFF for exactly as long as this runs
                // (`displaySheet.folding` -> the notch's Behavior), so the notch tracks the
                // fold frame by frame instead of chasing a moving target and lagging behind it
                // (patterns.md #48: two springs in a chain is a cascade). With the island
                // height instant, the card below slides down WITH the list, and nothing pops.
                // The wrapper is what the Column lays out, and it is ALWAYS visible with a
                // height that runs from -spacing (closed: cancels the Column gap exactly, so
                // the card at rest is the same size as with no list at all) to openH. Two
                // reasons over hiding the list at height 0: a hidden child drops its spacing
                // too, which popped the card by one gap at the start and end of every fold;
                // and the spring must UNDERSHOOT on the close as well (it is a spring, it
                // bounces on the settle in both directions), so the wrapper goes a few px
                // below rest and everything under it rises past its place and settles back.
                Item {
                    id: modeFold
                    width: parent.width
                    readonly property int rowH: 30 + 2
                    readonly property int rows: Math.min((card.mon.modes || []).length, 5)
                    readonly property real openH: rows * rowH - 2
                    // Snaps (no spring) while the sheet is hidden: modesOpenFor clears on hide
                    // and the collapse must not hold the notch's spring off for a hidden list.
                    property real fold: card.modesOpen ? 1 : 0
                    Behavior on fold { enabled: displaySheet.visible; NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier; onRunningChanged: displaySheet.folding += running ? 1 : -1 } }
                    height: fold * (openH + body.spacing) - body.spacing
                ListView {
                    anchors.top: parent.top
                    width: parent.width
                    height: Math.max(0, parent.height)
                    visible: height > 0.5
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: card.mon.modes || []
                    delegate: Rectangle {
                            id: mrow
                            required property var modelData
                            width: ListView.view.width
                            readonly property bool current: modelData.w === card.mon.width && modelData.h === card.mon.height && (!card.mon.hz || Math.round(modelData.rr) === Math.round(card.mon.hz))
                            height: 30
                            radius: Theme.rSm
                            color: mrowMa.containsMouse ? Theme.fillHigh : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                            StyledText { anchors.left: parent.left; anchors.leftMargin: Theme.s2; capCentreIn: parent; variant: "label"; text: mrow.modelData.label || ""; color: mrow.current ? Theme.hue("sliders") : Theme.inkPrimary }
                            StyledText { anchors.right: mtick.visible ? mtick.left : parent.right; anchors.rightMargin: Theme.s2; capCentreIn: parent; variant: "caption"; text: mrow.modelData.sublabel || ""; color: Theme.inkDim }
                            Icon { id: mtick; visible: mrow.current; anchors.right: parent.right; anchors.rightMargin: Theme.s2; anchors.verticalCenter: parent.verticalCenter; name: "check"; size: 14; color: Theme.hue("sliders") }
                            MouseArea { id: mrowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !Display.busy && !mrow.current; onClicked: { Display.setMode(card.mon.name, mrow.modelData.mode); displaySheet.modesOpenFor = ""; } }
                    }
                }
                }
            }
        }
    }
    StyledText { visible: Display.monitors.length === 0; variant: "label"; text: "No displays detected"; color: Theme.inkDim }

    // ── night light ──
    Rectangle {
        width: parent.width
        height: nlBody.implicitHeight + Theme.s3 * 2
        radius: Theme.rLg
        color: Theme.surfaceBase
        border.width: 1
        border.color: Theme.rim
        clip: true
        Column {
            id: nlBody
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.s3 }
            spacing: Theme.s2
            Item {
                width: parent.width
                height: 36
                CcSheetBits.Disc { tint: Theme.hue("sliders"); id: nlDisc; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; size: 32; icon: "night"; live: NightLight.enabled }
                Column {
                    anchors.left: nlDisc.right; anchors.leftMargin: Theme.s3
                    anchors.right: nlToggle.left; anchors.rightMargin: Theme.s3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    StyledText { variant: "label"; font.weight: Theme.wMedium; text: "Night Light"; color: Theme.inkPrimary }
                    StyledText { variant: "caption"; text: !NightLight.available && !NightLight.enabled ? "hyprsunset isn't installed" : NightLight.enabled ? (NightLight.temperature + " K") : "Off"; color: Theme.inkDim }
                }
                Toggle { id: nlToggle; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; enabled: NightLight.available || NightLight.enabled; opacity: enabled ? 1 : 0.4; checked: NightLight.enabled; onToggled: NightLight.toggle() }
            }
            // warmth: 6500 K (neutral) at the left, down to 1500 K (very warm) at the right.
            // Wrapped so it fades AND grows/shrinks in when Night Light flips: height is
            // instant (the island's single spring reveals it through the clip) and opacity
            // fades. The tint follows the drag LIVE (onMoved -> NightLight.setTemp, which
            // throttles the daemon socket call to ~90ms), and the disk write happens ONCE on
            // release: a Config write per mouse-move is a JSON serialise + file write + reload
            // each time and stalls the drag (patterns.md #49).
            Item {
                width: parent.width
                height: NightLight.enabled ? warmth.implicitHeight : 0
                clip: true
                opacity: NightLight.enabled ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                CcSheetBits.Track { tint: Theme.hue("sliders");
                    id: warmth
                    width: parent.width
                    icon: "night"
                    showPercent: false
                    value: 1 - (NightLight.temperature - 1500) / 5000
                    function kelvin(v) { return Math.round((1500 + (1 - v) * 5000) / 100) * 100; }
                    onMoved: v => NightLight.setTemp(kelvin(v))                      // tint live
                    onReleased: v => { NightLight.setTemp(kelvin(v)); Config.nightLightTemp = kelvin(v); }   // persist once
                }
            }
        }
    }
}
