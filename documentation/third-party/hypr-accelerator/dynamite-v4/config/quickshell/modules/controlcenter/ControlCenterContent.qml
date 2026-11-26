import QtQuick
import Quickshell
import "../../theme"
import "../../config"
import "../../services"
import "../../components"

// Control center guts, living inside the bar's island (see Bar.qml). The main view is a
// free-placement GRID of controls: which ones, where, and at what size all come from
// Config.ccItems (edited by drag and drop in Settings; the default arrangement is the
// macOS-Tahoe-style mosaic, connectivity capsules beside the now-playing card). Each
// control is a CcControl, which picks its presentation from its footprint, so this file
// only positions them and hosts the sub-views (Wi-Fi / Bluetooth / Audio / Display) that
// push over the grid with a slide+fade while the island resizes around them.
Item {
    id: root

    property bool active: false
    implicitHeight: column.implicitHeight
    clip: true

    property string view: "main"          // which sub-view we're in: main | wifi | bluetooth | audio | display
    // every sub-view opens as a SHEET over the grid, morphing out of the control that asked
    readonly property bool sheetOpen: view !== "main"
    // a list inside a sheet is folding open/closed on its own spring: the island's height
    // spring stands aside and tracks the content instantly for the duration (patterns.md #48)
    readonly property bool folding: dispSheetView.folding > 0
    // The sheet is a CONTAINER TRANSFORM: one progress value on the spring, and the sheet's
    // rect + corner radius are pure functions of it, from a 28px circle over the chevron
    // that asked for it to the full card (patterns.md #7: animate progress, derive geometry).
    // Closing runs the same path backwards, so it folds back into the chevron.
    property var sheetFrom: null          // rect in `views` coords; null = grow from the panel's centre
    property var sheetCtl: null           // the control whose chevron the sheet is wearing
    property real sheetT: sheetOpen ? 1 : 0
    Behavior on sheetT { NumberAnimation { id: sheetAnim; duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
    // The tile gets its chevron back only once the spring has actually finished, bounce
    // included. Gating on a threshold flickered: the overshoot dips t below zero and back,
    // and each crossing swapped which chevron was visible.
    readonly property bool sheetLive: sheetOpen || sheetAnim.running || sheetT > 0.001
    // A LINEAR clock for the close, 0 -> 1 over the same duration as the spring. Settle-phase
    // effects key off this, not off sheetT: the spring is under 0.05 by 37% of its duration
    // and spends the remaining 63% shrinking the last few px, bouncing and settling, so
    // anything tied to progress is finished long before the button has visibly arrived.
    property real closeClock: 0
    NumberAnimation { id: closeClockAnim; target: root; property: "closeClock"; from: 0; to: 1; duration: Theme.dur(Theme.dSpring); easing.type: Easing.Linear }
    onSheetOpenChanged: { if (sheetOpen) { closeClockAnim.stop(); closeClock = 0; } else closeClockAnim.restart(); }
    // Which sheet is showing, held for the whole fold. `view` flips back to "main" the
    // instant you press back, and the content columns used to key off it, so the card lost
    // its contents and collapsed to a header strip BEFORE it started folding. Latched here
    // until the spring has settled, the card folds with everything still in it.
    property string sheetView: ""
    onViewChanged: { ctxMenu.close(); if (view !== "main") sheetView = view; }
    readonly property string sheetKind: sheetCtl ? sheetCtl.originKind : "disc"
    onSheetLiveChanged: {
        if (sheetCtl) sheetCtl.chevronLent = sheetLive;
        if (!sheetLive) { sheetCtl = null; sheetView = ""; }
    }
    property var pskTarget: null
    readonly property var brightnessMon: Brightness.focused()
    readonly property int slide: Theme.s6   // how far the sub-views slide on push/pop


    function close() { GlobalState.controlCenterOpen = false; }
    function back() {
        if (ctxMenu.open) { ctxMenu.close(); return; }     // Esc peels the menu first
        if (view !== "main") { view = "main"; Network.setScanning(false); pskTarget = null; }
        else close();
    }
    // right-click menus for the sheets: `item`/x/y locate the click, mapped into the panel
    function openMenu(items, item, x, y) { const p = views.mapFromItem(item, x, y); ctxMenu.show(items, p.x, p.y); }

    onActiveChanged: {
        if (active) {
            view = "main";
            Display.refresh();
            Qt.callLater(() => keyCatcher.forceActiveFocus());
        } else {
            view = "main";
            pskTarget = null;
            Network.setScanning(false);
        }
    }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.active
        Keys.onEscapePressed: root.back()
    }

    function lockSoon() {
        // the lock backdrop is a grim screenshot of the desktop: close first and give
        // the island a beat to collapse, or the control center ends up IN the shot
        close();
        lockDelay.restart();
    }
    Timer { id: lockDelay; interval: 650; onTriggered: LockState.captureThenLock() }

    Column {
        id: column
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.s4

        // view container: overlaid views, push/pop slide + fade
        Item {
            id: views
            width: parent.width
            clip: true
            // The island's height. Gated on the INTENT (sheetOpen) not the animation tail
            // (sheetLive): on close this steps back to the grid at once, so the ONE spring
            // that smooths it (the notch's own height Behavior, always on) runs in parallel
            // with the sheet folding away, instead of holding tall and lurching down after.
            // A tall sheet (Sound/Display) thus shrinks WITH the card, the way the shorter
            // Wi-Fi/Bluetooth sheets already appeared to. `openH` follows content instantly
            // (no inner spring), so nothing here chases a moving target (patterns.md #7).
            // Instant binding to content: while a sheet is open the island tracks this exactly
            // (never clips the card), and the smoothness comes from the content's own spring
            // and, during transitions, the notch's height spring (gated by stableOpen).
            implicitHeight: root.sheetOpen ? Math.max(mainCol.implicitHeight, sheet.openH + Theme.s2 * 2)
                                           : mainCol.implicitHeight

            // MAIN: the grid. Positions come from Config.ccItems; this draws each control
            // at its cell footprint and animates it there when the layout changes. The model
            // is synced BY KEY (CcGridModel) so an edit moves a control in place instead of
            // rebuilding every delegate.
            Column {
                id: mainCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Theme.s3
                enabled: root.view === "main"     // the grid stays put under a sheet, just inert

                Item {
                    id: mosaic
                    width: parent.width
                    // cell geometry off the SETTLED config width (patterns.md #11), never the
                    // live one, so the island learns its final height on the first frame
                    readonly property real cell: Config.ccCell
                    readonly property int gap: Config.ccGap
                    height: Config.ccRows * cell + (Config.ccRows - 1) * gap
                    Behavior on height { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }

                    CcGridModel { id: gridModel }
                    Connections { target: Config; function onCcItemsChanged() { gridModel.sync(Config.ccItems); } }
                    Component.onCompleted: gridModel.sync(Config.ccItems)

                    Repeater {
                        model: gridModel
                        delegate: CcControl {
                            required property string ckey
                            required property int gx
                            required property int gy
                            required property int gw
                            required property int gh
                            key: ckey
                            w: gw
                            h: gh
                            cell: mosaic.cell
                            gap: mosaic.gap
                            x: gx * (mosaic.cell + mosaic.gap)
                            y: gy * (mosaic.cell + mosaic.gap)
                            width: implicitWidth
                            height: implicitHeight
                            Behavior on x      { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                            Behavior on y      { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                            Behavior on width  { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                            Behavior on height { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                            onMenu: k => {
                                // seed the transform at what was pressed, and take it over
                                // for the duration
                                const o = views.mapFromItem(null, origin.x, origin.y);
                                root.sheetFrom = Qt.rect(o.x, o.y, origin.width, origin.height);
                                root.sheetCtl = this;
                                chevronLent = true;
                                if (k === "wifi") { root.view = "wifi"; Network.setScanning(true); }
                                else if (k === "bluetooth") root.view = "bluetooth";
                                else if (k === "audio") root.view = "audio";
                                else if (k === "display") { root.view = "display"; Display.refresh(); }
                            }
                            onLockRequested: root.lockSoon()
                        }
                    }
                }
            }

            CcContextMenu { id: ctxMenu }

            // ── SHEET: every sub-view opens OVER the grid, not instead of it ───────────────
            // A panel floating inside the island: the grid stays where it is and dims under
            // a scrim, and the sheet rises over it at full width with its own header. You keep
            // the context you were looking at, nothing leaves the island, and Esc, the scrim
            // and the arrow all close it. Wi-Fi and Bluetooth still push (their lists want the
            // whole panel); moving them in here is a one-line change to `sheetOpen`.
            Rectangle {   // scrim
                anchors.fill: parent
                color: Theme.scrim
                opacity: Math.max(0, Math.min(1, root.sheetT))
                visible: opacity > 0
                MouseArea { anchors.fill: parent; onClicked: root.back() }
            }
            Rectangle {
                id: sheet
                // A container transform, the Android quick-settings way: the DISC behind the
                // chevron is the thing that becomes the card. One progress value on the shell's
                // spring; position, size and corner radius are pure functions of it, from the
                // disc's own rect to the centred card. The chevron cross-fades out IN PLACE
                // while the container grows around it; the card's content cross-fades in, laid
                // out at its final width and revealed by the clip. Close is the same path
                // backwards. Geometry reads the RAW progress on purpose, so the morph overshoots
                // and settles exactly like every other surface in the shell (the card lands a
                // few px large then relaxes, the disc lands a few px small then relaxes), only
                // floored so a big Bounce setting can never invert it.
                readonly property real openW: views.width - Theme.s2 * 2
                // Content that grows or shrinks while the sheet is AT REST (Wi-Fi switched off
                // and its list gone, a Bluetooth section appearing) resizes the card on the
                // spring, revealing or clipping the content as it goes, instead of snapping to
                // the new size. During the open/close morph itself the value follows the
                // content instantly so the transform always targets the true final size.
                // follows content instantly; the single height spring lives on `views`
                readonly property real openH: sheetCol.implicitHeight + Theme.s4 * 2
                readonly property real openX: Theme.s2
                readonly property real openY: Math.max(0, (views.height - openH) / 2)
                readonly property real t: root.sheetT
                readonly property real tc: Math.max(0, Math.min(1, t))
                // the source: the disc behind the chevron that was pressed, else the panel centre
                readonly property rect from: root.sheetFrom ? root.sheetFrom
                                           : Qt.rect(openX + openW / 2 - 13, openY + openH / 2 - 13, 26, 26)
                readonly property real w: Math.max(10, from.width + (openW - from.width) * t)
                readonly property real h: Math.max(10, from.height + (openH - from.height) * t)
                x: from.x + (openX - from.x) * t
                y: from.y + (openY - from.y) * t
                width: w
                height: h
                readonly property real fromR: root.sheetCtl ? root.sheetCtl.originRadius : 13
                radius: Math.min(w / 2, h / 2, fromR + (Theme.rXl - fromR) * tc)
                clip: true
                color: Theme.surfaceOverlay
                border.width: tc > 0.3 ? 1 : 0
                border.color: Theme.rim
                visible: root.sheetLive
                enabled: root.sheetOpen
                MouseArea { anchors.fill: parent }   // so a click inside never reaches the scrim

                // the disc's own fill, so frame 0 is the tile's disc pixel for pixel: the
                // hovered shade on the way out (a press is always under hover), the resting
                // shade on the way back (the pointer is on the back button by then). Fades as
                // the container becomes the card.
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: root.sheetCtl ? (root.sheetOpen ? root.sheetCtl.originTint : root.sheetCtl.originRest) : "transparent"
                    opacity: Math.max(0, 1 - sheet.tc / 0.3)
                    visible: opacity > 0
                }

                // a TILE origin: a live snapshot of the control that was pressed, pinned to its
                // spot, cross-fading exactly like the chevron does for a disc origin. hideSource
                // takes the real tile off the grid while this is live, so there is one copy.
                ShaderEffectSource {
                    z: 10
                    sourceItem: (root.sheetLive && root.sheetKind === "tile") ? root.sheetCtl : null
                    hideSource: true
                    x: sheet.from.x - sheet.x
                    y: sheet.from.y - sheet.y
                    width: sheet.from.width
                    height: sheet.from.height
                    opacity: root.sheetOpen ? Math.max(0, 1 - sheet.tc / 0.25)
                                            : Math.max(0, Math.min(1, (root.closeClock - 0.45) / 0.5))
                    visible: sourceItem !== null && opacity > 0
                }

                // the chevron, pinned to the disc's spot in panel coordinates. Open: it
                // cross-fades out over the first quarter while the container grows around it.
                // Close: it fades in over the second half of the close CLOCK (see closeClock):
                // from about when the disc has visibly arrived, through the bounce, landing at
                // full as the spring settles. The tile's own copy then takes over on the same
                // pixels at the same opacity.
                Icon {
                    z: 10
                    name: "chevron"
                    size: 14
                    x: (sheet.from.x + sheet.from.width / 2) - sheet.x - 7
                    y: (sheet.from.y + sheet.from.height / 2) - sheet.y - 7
                    color: Theme.inkDim
                    opacity: root.sheetOpen ? Math.max(0, 1 - sheet.tc / 0.25)
                                            : Math.max(0, Math.min(1, (root.closeClock - 0.45) / 0.5))
                    visible: root.sheetKind === "disc" && opacity > 0
                }

                // Content is laid out at the FINAL width from the start and revealed by the
                // clip as the card grows (never reflowed mid-morph), fading in over the second
                // half of the transform, the Material cross-fade.
                Column {
                    id: sheetCol
                    x: Theme.s4
                    y: Theme.s4
                    width: sheet.openW - Theme.s4 * 2
                    spacing: Theme.s4
                    opacity: Math.max(0, Math.min(1, (sheet.tc - 0.45) / 0.4))

                    // header: the way back, and which sheet this is
                    Item {
                        width: parent.width
                        height: 40
                        // the slider's button, in its "back" orientation: same disc, same
                        // shades, same glyph, pointing the other way
                        Item {
                            id: sheetBack
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26; height: 26
                            Rectangle {
                                anchors.fill: parent
                                radius: 13
                                color: sheetBackMa.containsMouse ? Theme.fillHigh : Theme.fillLow
                                Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                            }
                            Icon {
                                anchors.centerIn: parent
                                name: "chevron"
                                rotation: 180
                                size: 14
                                color: sheetBackMa.containsMouse ? Theme.accent : Theme.inkDim
                                Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                            }
                            MouseArea { id: sheetBackMa; anchors.fill: parent; anchors.margins: -7; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.back() }
                        }
                        StyledText {
                            id: sheetTitle
                            anchors.left: sheetBack.right
                            anchors.leftMargin: Theme.s3
                            // caps on the row's centre line, level with the disc and the toggle
                            // (logged 20.00 / 20.00 / 20.00); see StyledText.capCentreIn
                            capCentreIn: parent
                            variant: "header"
                            text: root.sheetView === "audio" ? "Sound"
                                : root.sheetView === "wifi" ? "Wi-Fi"
                                : root.sheetView === "bluetooth" ? "Bluetooth" : "Display"
                            color: Theme.inkPrimary
                        }
                        Toggle {
                            id: sheetToggle
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.sheetView === "wifi" || root.sheetView === "bluetooth"
                            checked: root.sheetView === "wifi" ? Network.wifiEnabled : Bluetooth.enabled
                            onToggled: root.sheetView === "wifi" ? Network.toggleWifi() : Bluetooth.toggle()
                        }
                    }

                    // SOUND and DISPLAY, each its own component
                    CcSoundSheet { width: parent.width; visible: root.sheetView === "audio"; panel: root }
                    CcDisplaySheet { id: dispSheetView; width: parent.width; visible: root.sheetView === "display"; panel: root }
                    // WI-FI and BLUETOOTH, each its own component (CcWifiSheet / CcBluetoothSheet)
                    CcWifiSheet { id: wifiSheetView; width: parent.width; visible: root.sheetView === "wifi"; panel: root }
                    CcBluetoothSheet { id: btSheetView; width: parent.width; visible: root.sheetView === "bluetooth"; panel: root }
                }
            }
        }
    }
}
