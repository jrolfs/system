import QtQuick
import QtQuick.Effects
import Quickshell
import "../../theme"
import "../../config"
import "../../services"
import "../../components"

// Wallpaper picker that lives INSIDE the bar island (the island morphs into it, see
// Bar.qml). A CAROUSEL, not a grid: five thumbnails across, the middle one held at
// centre and full size while the rest fall away by distance (same opacity falloff the
// date strip uses). Flick it with the arrows, the wheel, or by dragging; nothing is
// applied until you press Enter, so you can browse past a dozen wallpapers without the
// desktop strobing behind you. The one currently in use keeps an accent dot.
// Running into either end rubber-bands instead of stopping dead.
Item {
    id: root

    property bool active: false
    implicitHeight: col.implicitHeight
    clip: true

    // five across, 16:10-ish. The strip is one cell tall; the centre cell sits at scale 1
    // and its neighbours shrink, so nothing needs headroom above it.
    // Sized off the panel's SETTLED width, not its live one. The cell height feeds
    // implicitHeight, which is what the island animates its height toward. Read from the
    // animating width, the island could only learn how tall to be once it had finished
    // getting wide, so it expanded outward first and then downward, in two beats instead of
    // one motion. Off a constant, the final height is known on the first frame and both axes
    // travel together; the strip is still only as wide as the panel, so during the morph the
    // thumbnails are revealed rather than resized.
    readonly property int perView: 5
    readonly property int panelW: Math.max(240, Config.wallpaperPickerWidth - Theme.s4 * 2)
    readonly property int cellW: Math.floor(panelW / perView)
    readonly property int cellH: Math.round(cellW * 0.62)
    // Headroom for the hover lift. The strip has to clip horizontally, so without room set
    // aside the raised thumbnail (and its ring) would just get sliced off the top. The row
    // is cellH + 2*cellPad tall and the thumbnail sits centred in it, so the lift happens
    // INSIDE the clip.
    readonly property int liftPx: 3
    readonly property int cellPad: 8
    readonly property int rowH: cellH + cellPad * 2

    readonly property int count: Wallpapers.model?.count ?? 0

    function close() { GlobalState.wallpaperPickerOpen = false; }

    // Move by one, or rubber-band if that's the end of the road.
    function step(dir) {
        if (root.count === 0) return;
        const next = strip.currentIndex + dir;
        root.touched = true;
        if (next < 0 || next >= root.count) { strip.kick(dir); return; }
        strip.currentIndex = next;
    }

    // Apply the CENTRED one. This is the only thing that touches Config.wallpaper.
    // Moving through the carousel is free.
    function apply() {
        const m = Wallpapers.model;
        if (!m || m.count === 0 || strip.currentIndex < 0) return;
        const path = m.get(strip.currentIndex, "filePath");
        if (!path) return;
        Config.wallpaper = path;
    }

    // Open on whatever's already applied rather than at the far left. The folder model
    // populates asynchronously, so this gets called again when the count lands.
    function syncToCurrent() {
        const m = Wallpapers.model;
        if (!m || m.count === 0) return;
        for (let i = 0; i < m.count; i++) {
            if (m.get(i, "filePath") === Config.wallpaper) {
                strip.currentIndex = i;
                strip.jump(i);
                return;
            }
        }
    }

    // once the user has stepped, the folder model landing late must not yank the selection
    // back to the applied wallpaper under their keys
    property bool touched: false
    onActiveChanged: if (active) { touched = false; Qt.callLater(() => { keyCatcher.forceActiveFocus(); root.syncToCurrent(); }); }

    Connections {
        target: Wallpapers.model
        function onCountChanged() { if (root.active && !root.touched) Qt.callLater(root.syncToCurrent); }
    }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.active
        Keys.onEscapePressed: root.close()
        Keys.onReleased: event => { if (!event.isAutoRepeat && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) strip.release(); }
        Keys.onLeftPressed: root.step(-1)
        Keys.onRightPressed: root.step(1)
        Keys.onReturnPressed: root.apply()
        Keys.onEnterPressed: root.apply()
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.s3

        // header
        Item {
            width: parent.width
            height: 28
            StyledText {
                anchors.left: parent.left
                capCentreIn: parent
                variant: "header"
                text: "Wallpaper"
                color: Theme.inkPrimary
            }
            StyledText {
                anchors.right: parent.right
                capCentreIn: parent
                variant: "caption"
                text: root.count === 1 ? "1 image" : `${root.count} images`
                color: Theme.inkDim
            }
        }

        // the carousel
        Item {
            width: parent.width
            height: root.rowH

            ListView {
                id: strip
                // settled width, centred, from frame one
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.panelW
                orientation: ListView.Horizontal
                model: Wallpapers.model
                clip: true

                // ── the strip owns its scrolling ──
                // No highlight range, no snap mode: the view's range enforcement re-places
                // itself INSTANTLY whenever the current index moves against a fast highlight
                // animation (a left pressed mid-sweep jumped the strip 58px in one frame,
                // measured), and no amount of tuning changes that. Instead the content position
                // is animated explicitly: `go` stops whatever is in flight and starts a fresh
                // spring from wherever the strip IS to the centre of the index, so a reversal,
                // a burst or a hitch is always one continuous motion. `jump` places it
                // instantly (the open, a filter reset). A drag stops the animation and hands
                // the strip back to the nearest card on release.
                highlightRangeMode: ListView.NoHighlightRange
                highlightFollowsCurrentItem: false
                snapMode: ListView.NoSnap
                readonly property real pitch: root.cellW + spacing
                readonly property real centreOff: (width - root.cellW) / 2
                function xFor(i) { return i * pitch - centreOff; }
                function nearest() { return Math.max(0, Math.min(count - 1, Math.round((contentX + centreOff) / pitch))); }
                function go(i) { scroll.stop(); if (count === 0) return; scroll.from = contentX; scroll.to = xFor(i); scroll.start(); }
                function jump(i) { scroll.stop(); if (count === 0) return; contentX = xFor(i); }
                // a full card of travel per step: the island's longer entrance timing, not the
                // base spring, or the strip reads as snapping between cards
                NumberAnimation { id: scroll; target: strip; property: "contentX"; duration: Theme.dur(Theme.dEnter); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
                onDragStarted: scroll.stop()
                onMovementEnded: { const n = nearest(); if (n === currentIndex) go(n); else currentIndex = n; }
                // Room at both ends so the FIRST and LAST items can actually reach the centre.
                leftMargin: Math.max(0, (width - root.cellW) / 2)
                rightMargin: Math.max(0, (width - root.cellW) / 2)
                onCurrentIndexChanged: if (currentIndex >= 0) go(currentIndex)
                // dragging past either end rubber-bands rather than hitting a wall
                boundsBehavior: Flickable.DragOverBounds
                boundsMovement: Flickable.FollowBoundsBehavior

                // run-into-the-end rubber band: a pull, held while the KEY is held. A press
                // sets ONE target (the shove) and the spring carries the strip there; repeats
                // keep the same target, so nothing restarts (a new target per repeat restarted
                // the spring from a standstill 30 times a second and the strip spazzed). The
                // let-go follows the key's RELEASE, not a timer: the compositor's repeat delay
                // (~280ms here) is longer than any sensible timer, so a timed let-go dropped
                // the strip and the first repeat pulled it out again, every hold. The timer
                // stays only as a long fallback for a release that never arrives.
                property real bumpX: 0
                Behavior on bumpX { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                Timer { id: bumpBack; interval: 900; onTriggered: strip.bumpX = 0 }
                function kick(dir) { bumpX = -dir * 24; bumpBack.interval = 900; bumpBack.restart(); }
                // a tap releases within a few ms of pressing; give the pull a beat to show
                function release() { bumpBack.interval = Theme.dur(Theme.dFast); bumpBack.restart(); }
                transform: Translate { x: strip.bumpX }

                delegate: Item {
                    id: cell
                    required property int index
                    required property string filePath
                    required property url fileUrl

                    width: root.cellW
                    height: root.rowH

                    readonly property bool inUse: filePath === Config.wallpaper
                    readonly property bool centred: index === strip.currentIndex
                    // Distance from the centre of the viewport in CELL units, read off the live
                    // contentX rather than the index, so the falloff tracks a drag continuously
                    // instead of stepping when the current index flips.
                    readonly property real dist: Math.abs((x + width / 2) - (strip.contentX + strip.width / 2)) / Math.max(1, root.cellW)

                    opacity: 1 - Math.min(0.6, dist * 0.32)
                    scale: 1 - Math.min(0.2, dist * 0.1)
                    // nudges up under the pointer, so hovering visibly does something even
                    // though it still takes a click to select
                    transform: Translate {
                        y: cellMa.containsMouse ? -root.liftPx : 0
                        Behavior on y { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                    }

                    Item {
                        // the thumbnail itself keeps its own size, centred in the padded row
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.cellW - Theme.s1 * 2
                        height: root.cellH - Theme.s1 * 2

                        Image {
                            id: thumb
                            readonly property bool ready: status === Image.Ready && source.toString() !== ""
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize.width: 320
                            sourceSize.height: 200
                            source: cell.fileUrl
                            visible: false
                            layer.enabled: true
                        }
                        Rectangle {
                            id: thumbMask
                            anchors.fill: parent
                            radius: Theme.rMd
                            visible: false
                            layer.enabled: true
                        }
                        // placeholder under the art, so a not-yet-decoded thumb is a quiet
                        // surface rather than a hole punched in the strip
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.rMd
                            color: Theme.surfaceBase
                            visible: !thumb.ready
                        }
                        MultiEffect {
                            anchors.fill: parent
                            source: thumb
                            maskSource: thumbMask
                            maskEnabled: true
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                            // decoding is async, so fade the art up as it lands instead of
                            // letting it snap in a frame after the panel is already open
                            opacity: thumb.ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                        }

                        // ring on the CENTRED one (the one Enter will apply); a plain hairline
                        // on hover so the off-centre ones still read as targets
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.rMd
                            color: "transparent"
                            // hover has to be clearly brighter than idle; hairline was too close
                            // to invisible to read as a response
                            border.color: cell.centred ? Theme.accent
                                        : cellMa.containsMouse ? Theme.alpha(Theme.foreground, 0.45)
                                        : "transparent"
                            border.width: cell.centred ? 2 : 1
                            Behavior on border.color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                        }

                        // "this one's actually live" dot, so the applied wallpaper stays
                        // identifiable while you browse past it
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: Theme.s2
                            width: 8; height: 8
                            radius: 4
                            visible: cell.inUse
                            color: Theme.accent
                            border.width: 1
                            border.color: Theme.alpha(Theme.base, 0.45)
                        }

                        MouseArea {
                            id: cellMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // click an outer one to bring it to the middle; click the middle
                            // one to apply it (same as Enter)
                            onClicked: {
                                if (cell.centred) root.apply();
                                else strip.currentIndex = cell.index;
                            }
                        }
                    }
                }
            }

            // wheel anywhere over the strip steps through it. NoButton so it never eats the
            // clicks the thumbnails need (same trick the media zone uses in Bar.qml).
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y;
                    if (d !== 0) root.step(d < 0 ? 1 : -1);
                }
            }
        }

        // footer: what's centred, where you are, and how to commit it
        Item {
            width: parent.width
            height: 18

            StyledText {
                anchors.left: parent.left
                capCentreIn: parent
                width: parent.width * 0.6
                elide: Text.ElideMiddle
                variant: "caption"
                color: Theme.inkDim
                text: {
                    const m = Wallpapers.model;
                    if (!m || m.count === 0) return Wallpapers.dir === "" ? "No wallpaper folder set" : "No images in the wallpaper folder";
                    if (strip.currentIndex < 0) return "";
                    return m.get(strip.currentIndex, "fileName") ?? "";
                }
            }
            StyledText {
                anchors.right: parent.right
                capCentreIn: parent
                variant: "caption"
                color: Theme.inkFaint
                visible: root.count > 0
                text: `${strip.currentIndex + 1}/${root.count}   ·   Enter to apply`
            }
        }
    }
}
