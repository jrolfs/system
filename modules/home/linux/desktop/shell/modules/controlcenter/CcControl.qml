import QtQuick
import "../../config"
import "../../theme"

// One control at a given cell footprint: the dispatcher. Picks the presentation by the
// registry `kind` (Config.ccRegistry) and hands the tile a reference to itself (`ctl`) for
// its size, the cell geometry, and the two things a tile ever needs to ask the panel for:
// a sub-view (`menu`) or the screen lock. `interactive: false` is the layout editor's
// mode: the real visuals at the real size, none of the input.
Item {
    id: root

    property string key: ""
    property int w: 1
    property int h: 1
    property real cell: 64
    property int gap: 12
    property bool interactive: true
    signal menu(string key)
    signal lockRequested()
    // where the menu was asked for, in WINDOW coordinates: the tile sets this right before
    // emitting menu(), and the panel grows the sheet out of that spot (a container
    // transform, the Android way) instead of just fading it in
    property rect origin: Qt.rect(0, 0, 0, 0)
    // what the origin IS, so the sheet can start as it: "disc" (a slider's chevron button;
    // the sheet draws the chevron) or "tile" (a toggle's whole body; the sheet shows a live
    // snapshot of this control), its corner radius, and its fill in the pressed and
    // resting states
    property string originKind: "disc"
    property real originRadius: 13
    property color originTint: "transparent"
    property color originRest: "transparent"
    // true while the panel's sheet is animating out of (or back into) this control's
    // chevron: the tile hides its own copy so there is exactly ONE chevron on screen, the
    // one riding the sheet. Two visible at once is what read as "overlapping" on close.
    property bool chevronLent: false

    readonly property var reg: Config.ccReg(key)
    readonly property string kind: reg ? reg.kind : ""

    // ── metrics, derived from the cell ──
    // The grid runs 5 to 9 columns, which puts the cell anywhere from ~94px down to ~47px.
    // Everything a tile insets, sizes or centres comes from here instead of a fixed number,
    // or the same card is airy at 5 columns and overlapping at 9 (the slider cards' title
    // row and track were doing both). `k` is 1 at the default 7-column cell and every
    // constant below is the number the tiles used to hard-code, so nothing moves there.
    readonly property real k: cell / 64
    readonly property real discSize: Math.round(Math.max(26, Math.min(56, 44 * k)))    // the state circle
    readonly property real discInset: Math.max(4, Math.round((cell - discSize) / 2))   // which sits in a square
    readonly property real pad: Math.round(Math.max(6, Math.min(16, 12 * k)))          // a card's inset
    readonly property real glyph: Math.round(Math.max(13, Math.min(30, Theme.iconSize * k)))

    implicitWidth: w * cell + (w - 1) * gap
    implicitHeight: h * cell + (h - 1) * gap

    Component { id: toggleComp; CcToggleTile { ctl: root } }
    Component { id: sliderComp; CcSliderTile { ctl: root } }
    Component { id: mediaComp;  CcMediaTile { ctl: root } }
    Component { id: notifComp;  CcNotificationsTile { ctl: root } }

    Loader {
        anchors.fill: parent
        sourceComponent: (root.kind === "toggle" || root.kind === "action") ? toggleComp
                       : root.kind === "slider" ? sliderComp
                       : root.kind === "media" ? mediaComp
                       : root.kind === "notifications" ? notifComp
                       : null
    }
}
