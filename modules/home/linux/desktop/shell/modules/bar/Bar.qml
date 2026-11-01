import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../theme"
import "../../config"
import "../../services"
import "../../components"
import "../launcher"
import "../controlcenter"
import "../notifications"
import "../osd"
import "../wallpaper"
import "../logout"
import "../polkit"
import "../calendar"

// The notch (one per screen): a "dynamic island" that floats below the top edge
// (small gap above and below, all corners rounded, subtle shadow, the only bit of
// depth we let in). Collapsed it's the clock with the workspace capsules beside it (the
// group stays centred).
// Hover or click-to-pin springs it open to a media player (left), clock + date
// (center), and a control-center pill (right). Every size/radius/motion comes
// from Theme tokens. Modelled on notch-bar.html.
PanelWindow {
    id: bar

    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "quickshell:bar"
    anchors { top: true; left: true; right: true }
    // Reserve a strip so windows tile BELOW the island, with the gap under the
    // (collapsed) island matching the gap above it (topGap). Hyprland piles gaps_out
    // on top of the reserved edge, so subtract it or the two stack and the window
    // sits too far down. The wallpaper ignores this (fills the screen → no band).
    exclusionMode: ExclusionMode.Normal
    // game bar reserves its full height at the very top (no gap); otherwise reserve the
    // floating-island strip (gap above and below the collapsed island).
    // notch: no gap above (flush), so reserve just the notch height + the below gap.
    exclusiveZone: barForm ? gameBarH
                 : notchMode ? Math.max(0, topGap + collapsedH - gapsOut)
                 : Math.max(0, topGap * 2 + collapsedH - gapsOut)
    // Full-height ALWAYS: transparent and click-through via the mask except for the
    // island. Resizing the window on open (116 → full) is what gave us the morph flash,
    // 'cause the layer-surface reconfigure briefly yanked the island upward before it
    // settled. Keep it a constant size and opening the launcher never reconfigures the
    // window. Still anchored top/left/right (never bottom) so the exclusiveZone keeps
    // reserving only the strip and tiled windows sit below the island.
    implicitHeight: modelData?.height ?? 1600
    color: "transparent"
    // EXCLUSIVE keyboard focus while a panel's open so keystrokes stay with the
    // launcher/CC even under focus-follows-mouse (OnDemand let the pointer steal focus).
    WlrLayershell.keyboardFocus: morphWanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // input mask: the morph backdrop (click-outside) when a panel's open, else the bar
    // itself. In Game Mode a tall transient projects below the bar, so union in the
    // transientHost too, or clicks on the overflowing part fall through to the window
    // behind it.
    mask: Region {
        item: morphWanted ? backdrop : notch
        Region { item: (!bar.morphWanted && transientHost.shown) ? transientHost : null }
    }

    // The compositor blurs exactly the island's current outline, so the glass reads the
    // wallpaper through it and nothing around it. The notch's flares stay out of the region:
    // they are a few px of concave corner, and blurring their bounding box would leave a
    // blurred square past each curve. In Game Mode the panels that float below the bar get
    // their own regions.
    BackgroundEffect.blurRegion: Theme.blur ? blurShape : null
    readonly property Region blurShape: Region {
        item: notch
        topLeftRadius: Math.round(bar.notchTopR)
        topRightRadius: Math.round(bar.notchTopR)
        bottomLeftRadius: Math.round(bar.notchBR)
        bottomRightRadius: Math.round(bar.notchBR)
        Region {
            item: (bar.barForm && bar.morphWanted) ? morphHost : null
            radius: Theme.rIslandOpen
        }
        Region {
            item: (transientHost.overflow && transientHost.shown) ? transientHost : null
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: Theme.rIslandOpen
            bottomRightRadius: Theme.rIslandOpen
        }
    }

    property bool pinned: false
    readonly property bool expanded: hover.hovered || pinned || GlobalState.islandHold
    readonly property bool playing: Media.player?.isPlaying ?? false

    // When a panel closes with the cursor still over its (tall) area, the hover handler
    // would immediately report hovered → the island would flash its expanded/hover state
    // before shrinking below the cursor. Suppress hover for the collapse animation so it
    // drops straight to the collapsed notch/island instead; a fresh hover afterwards works.
    property bool closeGuard: false
    Timer { id: closeGuardTimer; interval: Theme.dur(Theme.dSpring) + 80; onTriggered: bar.closeGuard = false }
    onMorphWantedChanged: if (!morphWanted) { closeGuard = true; closeGuardTimer.restart(); }

    // launcher state: the island ITSELF morphs into the launcher, no extra layer
    readonly property bool onFocusedMon: (Hyprland.focusedMonitor?.name ?? "") === (modelData?.name ?? "x")
    // polkit (privilege escalation) is the top-priority morph: the agent drives it (not
    // a GlobalState toggle), and it SUPPRESSES the other panels so nothing open can ever
    // overlap an auth prompt.
    readonly property bool polkitWanted: Polkit.active && onFocusedMon
    readonly property bool launcherWanted: GlobalState.launcherOpen && onFocusedMon && !polkitWanted
    readonly property bool ccWanted: GlobalState.controlCenterOpen && onFocusedMon && !polkitWanted
    readonly property bool wallpaperWanted: GlobalState.wallpaperPickerOpen && onFocusedMon && !polkitWanted
    readonly property bool logoutWanted: GlobalState.logoutOpen && onFocusedMon && !polkitWanted
    readonly property bool calendarWanted: GlobalState.calendarOpen && onFocusedMon && !polkitWanted
    // any of these panels morphs the island; the window's full-height already, so this
    // just drives keyboard focus + the click-outside backdrop + the input mask.
    readonly property bool morphWanted: polkitWanted || launcherWanted || ccWanted || wallpaperWanted || logoutWanted || calendarWanted
    // a volume/brightness change morphs the island into a level pill (auto-hide), on the
    // monitor the OSD fired for. Beats a notification ('cause that's direct feedback to a
    // keypress), but never beats launcher/CC, those own the island.
    readonly property bool osdWanted: !morphWanted && OsdState.active && OsdState.screen === (modelData?.name ?? "")
    // a transient notification morphs the island to show it (auto-dismiss), but only
    // when idle (nothing else up: launcher/CC/OSD) and on the focused monitor.
    readonly property bool notifWanted: !morphWanted && !osdWanted && onFocusedMon && Notifications.showing !== null
    // Game Mode flattens the floating island into a full-width thin TOP BAR (squared,
    // edge-anchored, no gap) with a centred media | clock | cc cluster. It STAYS a bar
    // through everything, no morph-back flash. An OSD / notification / mode indicator
    // shows centred IN the bar (the cluster yields to it, the bar never shrinks back to
    // an island), and the morph panels (launcher, CC, pickers, settings, power, polkit)
    // float BELOW the bar via morphHost instead of expanding it. So barForm tracks Game
    // Mode alone; the osd/notif/morph states layer on top of it.
    readonly property bool barForm: GameMode.enabled
    // Notch mode: instead of the floating island, the bar hangs flush from the top edge
    // with SQUARE top corners and a ROUNDED bottom (a hardware-notch look). Toggled from
    // settings (Config.notchMode). Game Mode's full-width bar still wins over it.
    readonly property bool notchMode: Config.notchMode && !barForm

    // ── shape morph clocks ────────────────────────────────────────────────────────────────
    // Switching island↔notch used to hard-swap two different fills (a rounded Rectangle and
    // the teardrop Shape) via `visible`, so one popped out as the other popped in while the
    // geometry animated underneath. That was the chop. Now there's ONE shape that morphs,
    // driven by these. Everything positional reads them too, so the whole switch runs off a
    // single clock and nothing steps.
    property real notchT: notchMode ? 1 : 0        // 0 = island, 1 = notch
    Behavior on notchT { enabled: bar.morphAnim; NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
    // Entering Game Mode is INSTANT: it's the "give me frames" switch, so the bar just appears
    // (Theme.dur() is already 0 by then anyway) and this latch drops the morph Behaviors so
    // nothing animates on the way in. LEAVING is not latched: game mode is off, so the shell
    // is back to normal immediately, shadows and all, and the bar animates down to the island
    // the way every other morph does.
    property bool morphAnim: true
    onBarFormChanged: if (barForm) { morphAnim = false; morphAnimTimer.restart(); }
    Timer { id: morphAnimTimer; interval: 90; onTriggered: bar.morphAnim = true }
    property real barT: barForm ? 1 : 0            // 0 = island/notch, 1 = game bar
    Behavior on barT { enabled: bar.morphAnim; NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
    // how "flush to the top edge" we are; both the notch and the game bar sit flush. Derived,
    // so it's already continuous. Giving it its own Behavior would just chase a moving target.
    readonly property real flushT: Math.max(barT, notchT)

    // notch bottom radius (clamped to fit the current height) and the effective flare
    // (concave top-corner radius), clamped so the arcs always fit no matter the state.
    // real, not int: notch.rad interpolates continuously with the height, so rounding these to
    // whole px would re-quantize the corner into visible 1px jumps mid-animation.
    readonly property real notchBR: Math.min(notch.rad, notch.height / 2)
    readonly property real notchFlareRaw: Math.max(0, Math.min(Config.notchFlare, notch.height - notchBR, notch.width / 2))
    // TWO-PHASE morph, so the outline is well defined at every frame instead of trying to be a
    // rounded top and a flared top at once: for t<0.5 the top corners un-round, for t>0.5 the
    // flares grow out. Midpoint is a plain square-top / round-bottom slab, which reads fine.
    readonly property real notchFlareEff: notchFlareRaw * Math.max(0, 2 * notchT - 1)
    readonly property real notchTopR: notch.rad * Math.max(0, 1 - 2 * notchT)

    // SVG outline covering BOTH forms: rounded-top island (fr = 0, tr > 0) through to the
    // flared notch (fr > 0, tr = 0), with a rounded bottom either way. Local coords; the body
    // sits at x∈[fr, W-fr] and the flares stick out `fr` past each side at the top edge.
    // Radii near zero degrade to straight lines (a zero-radius SVG arc is undefined).
    function notchPath(bw, h, tr, br, fr) {
        var W = bw + 2 * fr;
        var L = fr, R = W - fr;
        var eps = 0.01;
        var p;
        // top-left: flare out, round in, or a hard corner
        if (fr > eps)      p = "M 0,0 A " + fr + "," + fr + " 0 0 1 " + L + "," + fr;
        else if (tr > eps) p = "M " + L + "," + tr;
        else               p = "M " + L + ",0";
        // left side down, across the bottom, back up the right
        if (br > eps) {
            p += " L " + L + "," + (h - br);
            p += " A " + br + "," + br + " 0 0 0 " + (L + br) + "," + h;
            p += " L " + (R - br) + "," + h;
            p += " A " + br + "," + br + " 0 0 0 " + R + "," + (h - br);
        } else {
            p += " L " + L + "," + h + " L " + R + "," + h;
        }
        // top-right, mirroring the top-left
        if (fr > eps) {
            p += " L " + R + "," + fr;
            p += " A " + fr + "," + fr + " 0 0 1 " + W + ",0";
        } else if (tr > eps) {
            p += " L " + R + "," + tr;
            p += " A " + tr + "," + tr + " 0 0 0 " + (R - tr) + ",0";
            p += " L " + (L + tr) + ",0";
            p += " A " + tr + "," + tr + " 0 0 0 " + L + "," + tr;
        } else {
            p += " L " + R + ",0";
        }
        return p + " Z";
    }
    readonly property int gameBarH: Config.gameBarHeight
    readonly property int gameClusterGap: Config.gameClusterGap // gap between each card and the clock in bar form

    readonly property int topGap: Config.islandGap  // gap above the island (and below it too, via exclusiveZone)
    readonly property int gapsOut: Config.hyprGapsOut // must match Hyprland general:gaps_out (top); subtract it or it stacks
    // The resting pill is at least the configured width, and grows to fit what the collapsed
    // clock row carries (capsules, glyphs) so verbose content never clips. Computed from the
    // row's SETTLED parts, never from timeRow.width: on a collapse the capsule and glyph
    // wrappers spring open over ~200ms, and a target that moved every frame restarted the
    // island's width animation every frame, so the island hung near its open width until
    // the wrappers settled and only then dropped (logged: 688 -> 568 in the first 200ms
    // while the target climbed 90 -> 252, then 16px a frame). One fixed target, one motion.
    readonly property bool dotsOn: Config.clockDots && ws.count > 0
    readonly property bool statusOn: Config.clockStatus && st.hasAny
    readonly property real restRowW: timeText.width
        + (dotsOn ? ws.restW + wsWrap.pad * 2 : 0)
        + (statusOn ? st.restW + stWrap.pad : 0)
        + ((dotsOn || statusOn) ? Theme.s5 - (dotsOn ? wsWrap.pad : 0) : 0) * ((dotsOn ? 1 : 0) + (statusOn ? 1 : 0))
    readonly property int collapsedW: Math.max(Config.islandCollapsedWidth, Math.round(restRowW) + 2 * Theme.s3 + Theme.s4)
    readonly property int collapsedH: Math.max(34, Config.barHeight + 4)
    // The expanded island is the pill, grown: the workspace capsules on the left and the
    // status glyphs on the right, both larger and with air around them, the clock with the
    // big time in the middle with the media card under it while something plays. Form
    // over function: nothing that is not already in the pill's vocabulary plus the one
    // card. The sides size to their content and take the same width so the clock sits
    // dead centre. With no player the island is the configured height with the time
    // centred; with one it grows to hold the card and the time lifts to the top. Each
    // part has its own Settings toggle.
    readonly property bool showWs: Config.islandWorkspaces && ws.count > 0
    readonly property bool showLedger: Config.islandStatus
    readonly property bool showNow: Config.islandMedia && Media.hasPlayer
    readonly property int sideW: Math.ceil(Math.max(ws.openW + 2 * wsBigPad, st.openW, 132)) + Theme.s3   // 132: room for an app name
    readonly property int wsBigPad: 8          // room for the active capsule's scale and glow
    readonly property int cardW: 300
    readonly property int cardH: 58
    readonly property int centreW: Math.max(Math.ceil(timeText.width * (Theme.fsClockBig / Theme.fsClock)) + 2 * Theme.s4, showNow ? cardW + 2 * Theme.s3 : 0)
    // the vertical plan with the card: the time's centre from the island's top, the card
    // centred in what is left under it
    readonly property int timeY: 36
    readonly property int timeBottom: timeY + 22
    readonly property int expandedContentW:
          2 * (Theme.s3 + Config.islandPadding)         // barRow left+right insets at full expand
        + (showWs ? sideW + Theme.s4 : 0)
        + (showLedger ? sideW + Theme.s4 : 0)
        + centreW
    readonly property int expandedW: Math.max(Config.islandMinWidth, expandedContentW)
    readonly property int cardGap: 5          // between the time and the card
    // 26 under the card = the air above the time's cap height (timeY minus half a cap), so
    // the time-plus-card block sits centred in the island
    readonly property int expandedH: showNow ? Math.max(Config.islandExpandedHeight, timeBottom + cardGap + cardH + 26) : Config.islandExpandedHeight
    // the time's lift off the island's centre line, 0 without the card
    readonly property real timeLift: showNow ? timeY - expandedH / 2 : 0
    readonly property int launcherW: Config.launcherWidth
    readonly property int ccW: Config.controlCenterWidth
    readonly property int calendarW: Config.calendarWidth       // the calendar's a compact morph
    readonly property int wallpaperW: Config.wallpaperPickerWidth // wallpaper picker wants room for big previews
    readonly property int polkitW: 460                          // the auth prompt: one column, no room needed for a grid
    readonly property int morphW: polkitWanted ? polkitW : calendarWanted ? calendarW : wallpaperWanted ? wallpaperW : ccWanted ? ccW : launcherW
    readonly property int notifW: Config.notificationWidth
    readonly property int osdW: Config.osdWidth

    // click-outside dismiss while the launcher's open (full-window, behind the island)
    MouseArea {
        id: backdrop
        anchors.fill: parent
        enabled: bar.morphWanted
        onClicked: {
            // polkit: click-outside CANCELS the auth request (fail closed), never a quiet close
            if (bar.polkitWanted) { if (Polkit.flow) Polkit.flow.cancelAuthenticationRequest(); return; }
            GlobalState.launcherOpen = false;
            GlobalState.controlCenterOpen = false;
            GlobalState.wallpaperPickerOpen = false;
            GlobalState.logoutOpen = false;
            GlobalState.calendarOpen = false;
        }
    }

    Item {
        id: notch
        anchors.top: parent.top
        // continuous: closes to 0 as it goes flush (notch or game bar). No Behavior here:
        // flushT is already animating, so one would just chase a per-frame target and stall.
        anchors.topMargin: bar.topGap * (1 - bar.flushT)
        anchors.horizontalCenter: parent.horizontalCenter

        // Game Mode: ALWAYS a full-width bar (osd/notif show centred inside it; morph
        // panels float below via morphHost, neither one resizes the bar horizontally).
        width: bar.barForm ? (modelData?.width ?? bar.expandedW)
             : bar.morphWanted ? bar.morphW
             : (bar.notifWanted || bar.osdWanted) ? transientHost.contentW
             : bar.expanded ? bar.expandedW : bar.collapsedW
        // Game Mode height: ALWAYS gameBarH, the bar never grows. A tall transient (a
        // notification) overflows DOWNWARD as a rounded-bottom projection (transientHost)
        // instead of stretching the whole bar. Normal mode: the island sizes to content.
        height: bar.barForm ? bar.gameBarH
              : bar.morphWanted ? morphHost.contentHeight
              : (bar.notifWanted || bar.osdWanted) ? transientHost.contentH
              : bar.expanded ? bar.expandedH : bar.collapsedH
        // Corner radius, DERIVED from the live (already-animated) height instead of stepped on
        // state. Stepping it snapped the corners to the collapsed radius the INSTANT you hovered
        // off (or closed a panel) while the island was still at full height, so they flashed
        // sharp for a beat until the shrink caught up. As a pure function of the current height
        // they're always right for the size the island actually is, at every frame of the
        // animation. Interpolates rIsland→rIslandOpen across the collapse↔expand range and caps
        // there, so tall morph/notification surfaces still round fully. Clamped to half the box
        // so the arcs always fit. Both the island Rectangle and the notch Shape read this, so
        // neither shape can drift from the other.
        // Ramps from the collapsed pill's radius to the open card's, then holds. The ramp has
        // to be height-derived (not a flat per-state value) or the corners desync from the size
        // mid-morph and visibly pop. But it saturates as soon as the surface is TALL ENOUGH to
        // draw the open radius (2*rIslandOpen), not at the expanded island's height. Ramping
        // all the way to expandedH meant every surface shorter than that got short-changed:
        // the power menu sat at 30.4 and the OSD at 21.4 while the launcher/CC/pickers were 31.
        // Now everything from ~62px up is exactly rIslandOpen, and the only surfaces below it
        // are ones physically too short to fit that corner (height/2 caps them).
        readonly property real radSat: 2 * Theme.rIslandOpen
        readonly property real rad: bar.barForm ? 0
              : Math.min(width / 2, height / 2,
                    Theme.rIsland + (Theme.rIslandOpen - Theme.rIsland)
                      * Math.max(0, Math.min(1, (height - bar.collapsedH)
                                                / Math.max(1, radSat - bar.collapsedH))))

        Behavior on width  { enabled: bar.morphAnim; NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
        // Width and height animate on the SAME always-on Behavior so a morph is uniform (both
        // axes together, never one then the other). The island height is the ONE spring for
        // content changes too: content resizes instantly, contentHeight steps, this springs
        // to it, and the root's clip reveals the content as the island grows (patterns.md #48).
        // The one exception: while a list inside the control center folds on ITS spring
        // (`controlCenter.folding`) this stands aside and tracks the content frame by frame,
        // so that fold is still the only spring and the island moves in lockstep with it.
        Behavior on height { enabled: bar.morphAnim && !controlCenter.folding; NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }

        // drop-in entrance
        opacity: 0
        transform: Translate { id: dropT; y: -22 }
        Component.onCompleted: dropAnim.start()
        ParallelAnimation {
            id: dropAnim
            NumberAnimation { target: notch; property: "opacity"; from: 0; to: 1; duration: Theme.dur(Theme.dEnter); easing.type: Easing.OutCubic }
            NumberAnimation { target: dropT; property: "y"; from: -22; to: 0; duration: Theme.dur(Theme.dEnter); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
        }

        // THE fill: one shape for every form. Island (rounded top + gap above), notch
        // (flush, square-ish top flaring out at the corners), and the game bar all come out
        // of the same outline, interpolated by bar.notchT / bar.barT. There's no second
        // surface to swap to, so switching modes can't pop: the corners un-round, the flares
        // grow, and the top margin closes on one clock.
        //
        // In notch mode it overshoots the top edge a few px (`over`) so it sits TRULY flush,
        // with no sliver of desktop above it. That overshoot scales to 0 as it becomes the
        // floating island, which needs its gap back.
        Shape {
            id: notchFill
            readonly property real over: 4 * bar.notchT
            anchors.top: parent.top
            anchors.topMargin: -over
            anchors.horizontalCenter: parent.horizontalCenter
            width: notch.width + 2 * bar.notchFlareEff
            height: notch.height + over
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            layer.enabled: Theme.shadows
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Theme.shadow
                shadowBlur: Theme.shadowBlur
                shadowVerticalOffset: Theme.shadowY
                blurMax: Theme.shadowBlurMax
                autoPaddingEnabled: true
            }
            ShapePath {
                fillColor: Theme.base
                // The light rim. In notch form the top edge sits in the `over` overshoot, off
                // screen, so the rim only traces the sides and bottom. The game bar has no
                // overshoot and spans the screen, where a rim would read as a 1px strip
                // holding it off the top, so it fades out there.
                strokeColor: Theme.rim
                strokeWidth: (1 - bar.barT)
                PathSvg {
                    path: bar.notchPath(notch.width, notch.height + notchFill.over,
                                        bar.notchTopR, bar.notchBR, bar.notchFlareEff)
                }
            }
        }

        // pin toggle: a press on any NON-interactive part of the island toggles pin.
        // Sits BELOW the content (declared before barRow), so the real buttons (cc pill,
        // media controls) grab their own clicks and only empty areas reach this. Replaces
        // a notch-wide TapHandler that fired even on the buttons.
        MouseArea {
            id: pinArea
            anchors.fill: parent
            enabled: !bar.morphWanted && !bar.notifWanted && !bar.osdWanted && !bar.barForm
            onClicked: bar.pinned = !bar.pinned
        }

        // bar content (media | clock): fades out as the island morphs
        RowLayout {
            id: barRow
            anchors.fill: parent
            // extra breathing room inside the EXPANDED island (7px on every side, on top of
            // the base s3 side inset). Animates via `pad` so the content eases inward as the
            // island opens instead of the margins jumping.
            property real pad: (bar.expanded && !bar.barForm) ? Config.islandPadding : 0
            Behavior on pad { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
            anchors.leftMargin: Theme.s3 + pad
            anchors.rightMargin: Theme.s3 + pad
            anchors.topMargin: pad
            anchors.bottomMargin: pad
            spacing: 0
            // clipped to the island: the content fades on dEffects while the island
            // shrinks on the longer spring, and the now-playing strip sits low enough that
            // it showed under the pill for a few frames of every collapse
            clip: true
            // hidden when an OSD/notification takes the bar, or when a panel morphs the
            // island in place (normal mode). In Game Mode the panels float BELOW, so the
            // bar cluster STAYS visible behind them.
            readonly property bool yielded: bar.osdWanted || bar.notifWanted || (bar.morphWanted && !bar.barForm)
            opacity: yielded ? 0 : 1
            enabled: !yielded
            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }

            // game-bar spacers: fill ONLY in bar form, centring the media|clock|cc cluster
            Item { Layout.fillWidth: bar.barForm }

            // LEFT COLUMN (expanded island only): the workspace capsules
            Item {
                id: wsZone
                readonly property bool act: bar.expanded && !bar.barForm && bar.showWs
                property real zw: act ? bar.sideW + Theme.s4 : 0
                Behavior on zw { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                Layout.preferredWidth: Math.max(0, zw)
                Layout.fillHeight: true
                clip: true
                opacity: act ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                // the focused app over the pill's capsules a size up, centred as a group
                Column {
                    id: wsCol
                    anchors.left: parent.left
                    anchors.leftMargin: bar.wsBigPad
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    IslandApp {
                        present: wsZone.act
                        maxW: bar.sideW - bar.wsBigPad
                    }
                    // room for the capsules' open home; the capsules are `ws` in the clock item
                    Item { id: wsSlot; width: ws.openW; height: ws.openCapH }
                }
            }

            // LEFT: media (game bar only)
            Item {
                id: leftZone
                // GAME BAR: the island's tall card (60px art + four stacked lines) is way taller
                // than gameBarH, so it used to overflow: art clipped top and bottom, transport
                // cut off below the edge entirely. In bar form the art shrinks to fit the bar and
                // the transport moves INLINE beside the text instead of under it, so the whole
                // thing is one short row.
                readonly property real artSize: bar.barForm
                    ? Math.max(16, Math.min(Config.mediaArtSize, bar.gameBarH - Theme.s2 * 2))
                    : Config.mediaArtSize
                // wide enough for the art + gap + the song-name column (settings-controlled),
                // plus the inline transport in bar form. Slack so text never touches the edge.
                // GAME BAR ONLY now: the expanded island carries no player and this zone
                // stays shut there.
                property real zw: bar.barForm ? (artSize + Theme.s3 + Config.mediaTitleWidth + Theme.s3) : 0
                // clamped: the spring UNDERSHOOTS past 0 on the way closed (that's the bounce,
                // by design), and a negative preferredWidth makes the layout hand the leftover
                // out differently for a few frames, which used to shove the clock sideways.
                Layout.preferredWidth: Math.max(0, zw)
                Layout.fillHeight: true
                clip: true
                opacity: bar.barForm ? 1 : 0
                Behavior on zw { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }

                // one transport button: a plain tinted glyph, no background chrome. Dims when
                // the action isn't available; tints to accent on hover.
                component MediaBtn: Item {
                    id: mb
                    property string glyph
                    property bool can: true
                    property int gsize: 18
                    signal act()
                    implicitWidth: 20; implicitHeight: 24
                    Icon {
                        anchors.centerIn: parent
                        name: mb.glyph
                        size: mb.gsize
                        color: !mb.can ? Theme.inkFaint : mbMa.containsMouse ? Theme.accent : Theme.inkPrimary
                    }
                    MouseArea {
                        id: mbMa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: mb.can
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mb.act()
                    }
                }

                // prev / play-pause / next. One definition, placed two ways: stacked under the
                // text in the island, inline beside it in the game bar (which has no vertical room).
                component TransportRow: Row {
                    spacing: Theme.s3
                    MediaBtn {
                        glyph: "prev"
                        can: Media.player?.canGoPrevious ?? false
                        onAct: Media.player?.previous()
                    }
                    MediaBtn {
                        glyph: bar.playing ? "pause" : "play"
                        gsize: 22
                        can: Media.player?.canTogglePlaying ?? (Media.hasPlayer)
                        onAct: Media.player?.togglePlaying()
                    }
                    MediaBtn {
                        glyph: "next"
                        can: Media.player?.canGoNext ?? false
                        onAct: Media.player?.next()
                    }
                }

                RowLayout {
                    id: mediaRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    // Width is pinned to the zone, NOT left implicit. Implicitly sized, the row
                    // grew to the song title's natural (unelided) width and overflowed leftZone,
                    // which clipped it mid-word. That's why the "…" never appeared. Bounded here,
                    // the text column can only ever get the room that's actually on screen.
                    width: leftZone.width
                    spacing: Theme.s3
                    transform: Translate { id: mediaT; y: 0 }

                    // album art: big rounded square (matches the inspo media card), masked
                    // and crossfaded on track change
                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: leftZone.artSize   // RowLayout sizes off Layout.*/implicit, not width
                        Layout.preferredHeight: leftZone.artSize
                        implicitWidth: leftZone.artSize; implicitHeight: leftZone.artSize

                        Rectangle {
                            id: artPlaceholder
                            anchors.fill: parent
                            radius: Math.min(Theme.rMd, leftZone.artSize * 0.28)   // match artMask
                            color: Theme.surfaceOverlay
                            opacity: artImg.ready ? 0 : 1     // crossfades with the art on change
                            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                            Icon {
                                anchors.centerIn: parent
                                name: "music"
                                color: Theme.accent
                            }
                        }
                        Image {
                            id: artImg
                            readonly property bool ready: status === Image.Ready && source.toString() !== ""
                            anchors.fill: parent
                            source: Media.player?.trackArtUrl ?? ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            visible: false
                            layer.enabled: true      // art masking, not a shadow, so always on
                        }
                        Rectangle {
                            id: artMask
                            anchors.fill: parent
                            // proportional, so the shrunken game-bar art stays a rounded SQUARE
                            // instead of collapsing into a circle at ~34px
                            radius: Math.min(Theme.rMd, leftZone.artSize * 0.28)
                            visible: false
                            layer.enabled: true      // art masking, not a shadow, so always on
                        }
                        MultiEffect {
                            anchors.fill: parent
                            source: artImg
                            maskEnabled: true
                            maskSource: artMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                            opacity: artImg.ready ? 1 : 0     // fade the new art in (was an abrupt pop)
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                        }
                    }

                    // title / album / artist / transport, stacked (matches the inspo card). Plain
                    // Column with an EXPLICIT width on every line (not a ColumnLayout + fillWidth):
                    // a Text only elides once its width is really set, and the layout-driven width
                    // was leaving them at natural size, so long names just got clipped by the zone
                    // mask. Single line each, NO wrapping: too long simply elides with a "…".
                    Column {
                        id: metaCol
                        Layout.alignment: Qt.AlignVCenter
                        // Line width = the configured song-name width, but NEVER wider than the
                        // room the zone actually has. Set mediaTitleWidth too high and the row no
                        // longer fits the island, so the layout squeezes leftZone below its
                        // preferred width. The texts still believed they were the full configured
                        // width, so elide never triggered and leftZone's clip just chopped them
                        // mid-word with no "…". Clamping to the real width makes elide fire at any
                        // setting; the config now reads as a maximum.
                        readonly property real lineW: width
                        Layout.fillWidth: true
                        Layout.maximumWidth: Config.mediaTitleWidth
                        spacing: 1

                        // title
                        StyledText {
                            id: titleText
                            width: metaCol.lineW
                            text: Media.player?.trackTitle ?? "Nothing playing"
                            font.weight: Theme.wSemiBold
                            font.pixelSize: Theme.fsBody
                            color: Theme.inkPrimary
                            elide: Text.ElideRight
                        }
                        // album
                        StyledText {
                            width: metaCol.lineW
                            visible: Config.mediaShowAlbum && text !== "" && !bar.barForm
                            text: Media.player?.trackAlbum ?? ""
                            font.pixelSize: Theme.fsCaption
                            color: Theme.inkDim
                            elide: Text.ElideRight
                        }
                        // artist
                        StyledText {
                            width: metaCol.lineW
                            visible: Config.mediaShowArtist && text !== ""
                            text: Media.player?.trackArtist ?? ""
                            font.pixelSize: Theme.fsCaption
                            color: Theme.inkFaint
                            elide: Text.ElideRight
                        }
                        // transport, stacked under the text. ISLAND ONLY: the game bar has no
                        // vertical room for it and shows just art + title/artist.
                        Item {
                            visible: Config.mediaShowTransport && !bar.barForm
                            width: metaCol.lineW
                            height: visible ? stackedTransport.height + 4 : 0   // the 4 is the gap above the row
                            TransportRow { id: stackedTransport; anchors.bottom: parent.bottom }
                        }
                    }

                }

                // Scroll over the MEDIA (left side only) to switch tracks: down → next,
                // up → prev (switches songs, doesn't seek). Scoped to leftZone so scrolling
                // the clock does nothing. MouseArea.onWheel, 'cause WheelHandler doesn't get
                // wheel on this layer surface; NoButton so it never eats clicks.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: (wheel) => {
                        const dy = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y;
                        if (Config.mediaScrollSwitch && bar.expanded && dy !== 0) leftZone.switchTrack(dy < 0 ? -1 : 1);
                    }
                }

                property int slideDir: -1   // -1 = next (media enters from below), +1 = prev (from above)
                property bool scrollSwitch: false   // a scroll knows the direction; app-initiated changes don't
                function switchTrack(dir) {
                    const p = Media.player;
                    if (!p || mediaCooldown.running) return;
                    if (dir < 0 ? !p.canGoNext : !p.canGoPrevious) return;
                    leftZone.slideDir = dir;
                    leftZone.scrollSwitch = true;
                    if (dir < 0) p.next(); else p.previous();
                    mediaCooldown.restart();
                }
                Timer { id: mediaCooldown; interval: 300 }

                // Animate EVERY track change (scroll OR app-initiated): the whole media row
                // (art + title/artist) slides in from slideDir. NEXT enters from below (moves
                // up), PREV enters from above (moves down), opposite so they read distinctly.
                property string curTitle: Media.player?.trackTitle ?? ""
                onCurTitleChanged: {
                    // scroll → directional slide (we know next vs prev); app-initiated change
                    // → neutral crossfade, 'cause MPRIS can't report direction so don't fake one.
                    if (leftZone.scrollSwitch) mediaSlideIn.restart();
                    else mediaCrossfade.restart();
                    leftZone.scrollSwitch = false;
                }
                // SCROLL switch: directional slide. NEXT enters from below (moves up), PREV
                // from above (moves down). Starts partly visible so the direction reads.
                SequentialAnimation {
                    id: mediaSlideIn
                    readonly property int dist: 20
                    PropertyAction { target: mediaT; property: "y"; value: -leftZone.slideDir * mediaSlideIn.dist }
                    PropertyAction { target: mediaRow; property: "opacity"; value: 0.4 }
                    ParallelAnimation {
                        NumberAnimation { target: mediaT; property: "y"; to: 0; duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
                        NumberAnimation { target: mediaRow; property: "opacity"; to: 1; duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
                    }
                }
                // APP-initiated change: a plain crossfade, no slide so no direction's implied.
                SequentialAnimation {
                    id: mediaCrossfade
                    PropertyAction { target: mediaT; property: "y"; value: 0 }
                    PropertyAction { target: mediaRow; property: "opacity"; value: 0 }
                    NumberAnimation { target: mediaRow; property: "opacity"; to: 1; duration: Theme.dur(Theme.dBase); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
                }
            }

            // inner gap (bar form only): separates media from the clock so the cards sit
            // further out while the cluster stays centred (paired with the right one below).
            Item { Layout.preferredWidth: bar.barForm ? bar.gameClusterGap : 0 }

            // CENTER: clock. Fills the middle (island); in bar form it's natural-width so
            // the outer fill-spacers centre the cluster and the inner gaps spread it out.
            Item {
                id: clock
                // the date beside the time in the open island: 0 = time alone, centred;
                // 1 = time slid left, date in on its right
                property real dateT: (bar.expanded && !bar.barForm) ? 1 : 0
                Behavior on dateT { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                readonly property real dateGap: 10
                readonly property real dateRoom: (bar.expanded && !bar.barForm) ? dateGap + dateText.implicitWidth : 0   // the settled target, for the box
                Layout.fillWidth: !bar.barForm
                Layout.preferredWidth: bar.barForm ? timeRow.width : 0
                Layout.fillHeight: true

                // subtle "button" affordance behind the time/date: a faint fill shows on
                // hover so the clock reads as pressable; pressing it morphs the island into
                // the calendar. Only active in the clock's full form (expanded island or game
                // bar); collapsed, clicks fall through to the pin toggle.
                Rectangle {
                    id: clockBtn
                    readonly property real sf: (bar.expanded && !bar.barForm) ? (Theme.fsClockBig / Theme.fsClock) : 1
                    // The clock sits in the MIDDLE of what the side columns leave, which is the
                    // island's centre when both are on. Pure binding, NO Behavior on x: the
                    // zones' widths already animate, so the slide is smooth, and a Behavior
                    // would chase a target that moves every frame and visibly stall.
                    //
                    // Written against barRow (NOT the clock item) on purpose. The RowLayout hands
                    // `clock` INTEGER x/width, so while the spring settles its bounce arrives as 1px
                    // steps. That was the clock snapping sideways at the end of a collapse. The
                    // middle of the free span is (barRow.width + left - right) / 2 in barRow
                    // coordinates, all continuous values, and clock.x only converts it back.
                    x: bar.barForm ? (clock.width - width) / 2
                                   : (barRow.width + Math.max(0, wsZone.zw) - Math.max(0, ledgerZone.zw)) / 2
                                     - clock.x - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: (bar.expanded && !bar.barForm) ? bar.timeLift : 0
                    // sized from the TIME alone, never from timeRow.width: on an expand the
                    // capsule and glyph wrappers are still folding away inside that row for
                    // the length of the spring, and a width that followed it retargeted every
                    // frame, so the hover box sat wide for a beat and shrank late (the stall
                    // in patterns.md #64). One target: the big time plus a rectangle's worth
                    // of padding, more at the sides than above and below.
                    width: timeText.width * sf + clock.dateRoom + 2 * Theme.s4
                    height: Math.round(clockFm.height * sf) + 2 * Theme.s2
                    radius: Theme.rMd
                    visible: bar.expanded || bar.barForm
                    color: clockMa.containsMouse ? Theme.fillLow : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                    Behavior on width { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                }

                Row {
                    id: timeRow
                    // centred on the clock button; lifted to the top while the media card sits
                    // under it, on the island's centre line otherwise. The lift animates as a
                    // number (not the font) so it stays smooth.
                    property real shift: (bar.expanded && !bar.barForm) ? bar.timeLift : 0
                    Behavior on shift { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                    // the capsule wrapper's left glow margin is dead space; pull the row back
                    // by exactly half of it so the content BOX sits centred (measured 25.6 /
                    // 21.6 before). What remains is glyph side-bearing: the time's last digit
                    // changes every minute (a 0 reaches further right than a 1), so the ink
                    // margin wobbles by up to a pixel on its own. Centring on the box keeps the
                    // pill still; centring on the ink would nudge it every minute.
                    x: clockBtn.x + (clockBtn.width - width) / 2 - (wsWrap.act ? wsWrap.pad / 2 : 0)
                       - clock.dateT * (clock.dateGap + dateText.implicitWidth) / 2   // slides left to make room for the date
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: shift
                    spacing: (wsWrap.act || stWrap.act) ? Theme.s5 - (wsWrap.act ? wsWrap.pad : 0) : 0
                    Behavior on spacing { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }

                    // workspace dots, left of everything, collapsed only (the dial takes the
                    // expanded island). Reveal: width to 0 on the spring,
                    // fade, a little scale, clipped.
                    // room for the workspace capsules at rest, collapsed only. The capsules
                    // themselves are `ws` below (one set, two homes); this only holds their
                    // place in the row and gives it back on the spring as the island opens.
                    Item {
                        id: wsWrap
                        readonly property bool act: Config.clockDots && !bar.expanded && !bar.barForm && ws.count > 0
                        // a margin each side for the active capsule's scale and glow
                        readonly property int pad: 6
                        width: act ? ws.restW + pad * 2 : 0
                        height: 1
                        Behavior on width { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                    }

                    // Time. Sits DIRECTLY in the Row (not in a scale-tracking wrapper) on purpose:
                    // an item's width ignores its `scale` transform, so timeRow.width stays CONSTANT
                    // while the time scales up. clockBtn.width keys off it (times the step `sf`), so
                    // the button has one fixed target its Behavior can animate to cleanly. Wrapping
                    // this to report the animating scaled width made timeRow.width change every
                    // frame, so clockBtn's width Behavior chased a moving target and the whole clock
                    // stalled/stuttered on hover, the same trap as a Behavior on x. Don't reintroduce it.
                    // The time, drawn per digit so the digits can ROLL, iPhone-lock-screen
                    // style: when a digit changes, the old glyph slides up and fades out while
                    // the new one rises into its place fading in, masked to the line box. Only
                    // the digits that actually change move (onChChanged fires per cell); the
                    // rest hold perfectly still.
                    //
                    // Cells take each character's PROPORTIONAL advance (no tabular figures:
                    // tnum gave "1" a full digit slot and the time read gap-toothed). Widths
                    // change only AT the tick, a discrete step identical to what the single
                    // Text used to do, and clockBtn's width Behavior smooths it; during the
                    // roll itself nothing resizes, so there's still no per-frame churn.
                    Row {
                        id: timeText
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        transformOrigin: Item.Center
                        scale: (bar.expanded && !bar.barForm) ? (Theme.fsClockBig / Theme.fsClock) : 1.0
                        // optical centre: the digits' cap height sits below the text box's
                        // middle (measured 1.6px low against the notch's centre line, which
                        // the flat top edge makes easy to see), so the glyphs ride up a touch
                        transform: Translate { y: -1.5 }
                        Behavior on scale { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }

                        readonly property string timeStr: Qt.formatDateTime(sysclock.date, (Config.clock24h ? "HH:mm" : "h:mm") + (Config.clockSeconds ? ":ss" : "") + (Config.clock24h ? "" : " AP"))
                        SystemClock { id: sysclock; precision: Config.clockSeconds ? SystemClock.Seconds : SystemClock.Minutes }

                        FontMetrics {
                            id: clockFm
                            font.family: Theme.fontDisplay
                            font.pixelSize: Theme.fsClock
                            font.weight: Theme.wSemiBold
                        }

                        Repeater {
                            model: timeText.timeStr.length
                            delegate: Item {
                                id: cell
                                required property int index
                                readonly property string ch: timeText.timeStr.charAt(cell.index)

                                width: chM.advanceWidth
                                height: clockFm.height
                                clip: true                        // the mask that sells the roll

                                TextMetrics {
                                    id: chM
                                    font.family: Theme.fontDisplay
                                    font.pixelSize: Theme.fsClock
                                    font.weight: Theme.wSemiBold
                                    text: cell.ch
                                }

                                // what's on screen; lags ch by one roll
                                property string shown: ""
                                property bool ready: false
                                Component.onCompleted: { shown = ch; ready = true; }
                                onChChanged: {
                                    if (!cell.ready || cell.shown === cell.ch) return;
                                    outT.text = cell.shown;
                                    cell.shown = cell.ch;
                                    roll.restart();
                                }

                                component ClockGlyph: Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    font.family: Theme.fontDisplay
                                    font.pixelSize: Theme.fsClock
                                    font.weight: Theme.wSemiBold
                                    color: Theme.inkPrimary
                                    renderType: Text.QtRendering
                                }

                                ClockGlyph { id: curT; text: cell.shown; y: 0 }
                                ClockGlyph { id: outT; opacity: 0 }

                                ParallelAnimation {
                                    id: roll
                                    // incoming: rises from below into place
                                    NumberAnimation { target: curT; property: "y"; from: cell.height * 0.6; to: 0; duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
                                    NumberAnimation { target: curT; property: "opacity"; from: 0; to: 1; duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
                                    // outgoing: keeps travelling up and out
                                    NumberAnimation { target: outT; property: "y"; from: 0; to: -cell.height * 0.6; duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
                                    NumberAnimation { target: outT; property: "opacity"; from: 1; to: 0; duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
                                }
                            }
                        }
                    }

                    // battery + Wi-Fi's room, right of the time, collapsed only: the mirror of
                    // the capsules' spacer. The glyphs themselves are `st` in the clock item,
                    // one set with two homes.
                    Item {
                        id: stWrap
                        readonly property bool act: Config.clockStatus && st.hasAny && !bar.expanded && !bar.barForm
                        // the same dead margin the workspace wrapper carries on its clock side,
                        // so the gap from the time to each side's ink is identical
                        readonly property int pad: wsWrap.pad
                        width: act ? st.restW + pad : 0
                        height: 1
                        Behavior on width { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                    }
                }

                // The date, right of the time, open island only: "Tue, Sep 21" in a quiet gray.
                // It slides in from where the time's centre was and fades up while the time
                // slides left; both ride dateT, so they are one motion.
                StyledText {
                    id: dateText
                    // from the TIME's own right edge (it scales about its centre), not the
                    // row's: while the capsule and glyph room re-grows on a close the time is
                    // no longer the row's centre, and the date rode into it
                    // and from the time's LIVE scale (timeText.scale animates on the spring)
                    // rather than clockBtn.sf, which steps the moment the state flips and
                    // put the slot 9px into the digits for the first frames of a close
                    readonly property real slot: timeRow.x + timeText.x + timeText.width / 2 + timeText.width * timeText.scale / 2 + clock.dateGap
                    x: slot - (1 - clock.dateT) * 20
                    anchors.verticalCenter: parent.verticalCenter
                    // centred on the digits' ink, not their baseline (measured against the
                    // time's ink centre: +3 sat 5px low, 0 1px low, -2 1px high)
                    anchors.verticalCenterOffset: timeRow.shift - 1
                    text: Qt.formatDateTime(sysclock.date, "ddd, MMM d")
                    font.pixelSize: Theme.fsBody
                    font.weight: Theme.wMedium
                    color: Theme.inkDim
                    // gone by a third of the way: it slides back under the time on a close,
                    // and fading on the same clock as the slide left it legible over the digits
                    opacity: Math.max(0, Math.min(1, (clock.dateT - 0.35) / 0.65))
                    visible: opacity > 0.01
                }

                // The media card, under the time, centred in what the island has below it.
                // Expanded only; the game bar keeps its inline card on the left.
                IslandMedia {
                    id: mediaCard
                    x: clockBtn.x + (clockBtn.width - width) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: bar.timeBottom + bar.cardGap + bar.cardH / 2 - bar.expandedH / 2
                    cardW: bar.cardW
                    cardH: bar.cardH
                    live: bar.expanded && !bar.barForm && bar.showNow
                    opacity: live ? 1 : 0
                    visible: Config.islandMedia && opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                }

                // THE workspace capsules, one set with two homes (IslandDots): at rest in
                // the pill's row, where the wsWrap spacer holds their room, open in the left
                // column, where the wsSlot holds it. Both homes are handed over in THIS
                // item's coordinates from the spacers' live positions, so each capsule glides
                // from the centre to the left and back as the island morphs, one after
                // another, instead of one set vanishing and another appearing.
                IslandDots {
                    id: ws
                    screen: bar.modelData
                    anchors.fill: parent
                    open: bar.expanded && !bar.barForm
                    restOn: Config.clockDots && !bar.barForm
                    openOn: bar.showWs
                    // the rest row ends one row-gap left of the TIME's visible left edge (its
                    // live scale included), not at the wsWrap spacer: the spacer folds to 0
                    // as the island opens and the row recentres, which slid the capsules
                    // still waiting their turn under the growing digits. With the pill at
                    // rest this is exactly wsWrap.x + pad.
                    restX: timeRow.x + timeText.x + timeText.width / 2 - timeText.width * timeText.scale / 2 - Theme.s5 - ws.restW
                    restY: timeRow.y + timeRow.height / 2
                    openX: wsZone.x - clock.x + wsCol.x + wsSlot.x
                    openY: wsZone.y - clock.y + wsCol.y + wsSlot.y + wsSlot.height / 2
                    openCapW: 9; openCapH: 17; openGap: 7
                }

                // THE status glyphs, the same arrangement mirrored: one set with two homes,
                // at rest right of the time where the stWrap spacer holds their room, open
                // in the right column where stSlot holds it. Battery first on the way out,
                // the bars behind it tallest first, retracting from the far end on the way
                // home.
                IslandStatus {
                    id: st
                    anchors.fill: parent
                    open: bar.expanded && !bar.barForm
                    restOn: Config.clockStatus && st.hasAny && !bar.barForm
                    openOn: bar.showLedger
                    // the rest row starts one row-gap right of the TIME's visible right edge
                    // (its live scale included), the capsules' rule mirrored; with the pill
                    // at rest this is exactly stWrap.x + pad
                    restX: timeRow.x + timeText.x + timeText.width / 2 + timeText.width * timeText.scale / 2 + Theme.s5 + (bar.dotsOn ? 0 : wsWrap.pad)
                    restY: timeRow.y + timeRow.height / 2
                    openX: ledgerZone.x - clock.x + ledgerCol.x + stSlot.x
                    openY: ledgerZone.y - clock.y + ledgerCol.y + stSlot.y + stSlot.height / 2
                    openCapH: 17; openBarW: 4; openGap: 10; openBattW: 36; openBattH: 17
                }

                // press target: opens the calendar. Sits on top of the text so it grabs the
                // click instead of the pin-toggle behind the island.
                MouseArea {
                    id: clockMa
                    anchors.fill: clockBtn
                    enabled: bar.expanded || bar.barForm
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: GlobalState.toggleCalendar()
                }
            }

            // RIGHT COLUMN (expanded island only): the status glyphs
            Item {
                id: ledgerZone
                readonly property bool act: bar.expanded && !bar.barForm && bar.showLedger
                property real zw: act ? bar.sideW + Theme.s4 : 0
                Behavior on zw { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                Layout.preferredWidth: Math.max(0, zw)
                Layout.fillHeight: true
                clip: true
                opacity: act ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                // the inbox over the pill's glyphs a size up, right-aligned as a group: the
                // mirror of the app over the capsules on the left
                Column {
                    id: ledgerCol
                    anchors.right: parent.right
                    anchors.rightMargin: bar.wsBigPad
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    IslandInbox {
                        present: ledgerZone.act
                        maxW: bar.sideW - bar.wsBigPad
                        anchors.right: parent.right
                    }
                    // room for the glyphs' open home; the glyphs are `st` in the clock item
                    Item { id: stSlot; width: st.openW; height: st.openCapH; anchors.right: parent.right }
                }
            }

            // game-bar trailing spacer (fills only in bar form): pairs with the leading
            // one to keep the media | clock cluster centred on the full-width bar.
            Item { Layout.fillWidth: bar.barForm }
        }

        HoverHandler { id: hover; enabled: !bar.morphWanted && !bar.notifWanted && !bar.osdWanted && !bar.barForm && !bar.closeGuard }
    }

    // transient host: OSD + notification + mode indicator. NORMAL mode: coincides with
    // the notch (rides notch.fill), so the island morphs to the content like before. GAME
    // mode: the notch stays a gameBarH bar, so this sits centred IN it; if the content is
    // TALLER than the bar it does NOT stretch the bar, it overflows DOWNWARD as a
    // rounded-bottom projection (squared top so it merges into the bar, like a tab
    // hanging off it). Single instances; the notch references these ids for normal sizing.
    Item {
        id: transientHost
        readonly property bool shown: bar.notifWanted || bar.osdWanted
        // the notification gets more air than the OSD capsule: it's taller, so its corners
        // reach the island's full open radius and the text needs to clear them
        readonly property int contentH: bar.notifWanted ? (notifIsland.implicitHeight + Theme.s5 * 2)
              : bar.osdWanted ? (osdIsland.implicitHeight + Theme.s3 * 2)
              : bar.collapsedH
        readonly property int contentW: bar.notifWanted ? bar.notifW
              : bar.osdWanted ? (OsdState.kind === "mode" ? (osdIsland.modeWidth + Theme.s5 * 2) : bar.osdW)
              : bar.collapsedW
        // game mode + content taller than the bar → it projects below the bar
        readonly property bool overflow: bar.barForm && contentH > bar.gameBarH

        anchors.top: parent.top
        anchors.topMargin: bar.topGap * (1 - bar.flushT)   // rides the same clock as the notch
        anchors.horizontalCenter: parent.horizontalCenter
        // NORMAL mode: clip the (fixed-width, centred) content to the notch while it grows
        // from collapsed → full, or the icon/%/label hang outside the pill onto the
        // wallpaper for a frame before the background catches up. The content gets revealed
        // as the pill expands instead. GAME mode: don't clip, 'cause the bar's already full
        // width (no overflow) and clipping would cut the projection's drop shadow.
        clip: !bar.barForm
        // game: own footprint, growing DOWN past the bar for tall content. normal: ride
        // the notch exactly (the island is the animated surface; this just follows it).
        width: bar.barForm ? contentW : notch.width
        height: bar.barForm ? Math.max(bar.gameBarH, contentH) : notch.height
        Behavior on width  { enabled: bar.barForm; NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
        Behavior on height { enabled: bar.barForm; NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }

        // the projection background: drawn ONLY in Game Mode when the content overflows
        // the bar. Squared top (flush with / merging into the bar), rounded bottom so it
        // reads as a tab projecting out of the bar.
        Rectangle {
            id: projFill
            anchors.fill: parent
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: Theme.rIslandOpen
            bottomRightRadius: Theme.rIslandOpen
            color: Theme.base
            antialiasing: true
            visible: transientHost.overflow
            opacity: transientHost.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
            layer.enabled: Theme.shadows
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Theme.shadow
                shadowBlur: Theme.shadowBlur
                shadowVerticalOffset: Theme.shadowY
                blurMax: Theme.shadowBlurMax
                autoPaddingEnabled: true
            }
        }

        NotificationIsland {
            id: notifIsland
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: bar.notifW - Theme.s5 * 2
            notif: Notifications.showing
            opacity: bar.notifWanted ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
        }
        OsdIsland {
            id: osdIsland
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: OsdState.kind === "mode" ? osdIsland.modeWidth : (bar.osdW - Theme.s5 * 2)
            opacity: bar.osdWanted ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
        }
    }

    // morph panels host (launcher / control center / pickers / settings / power /
    // polkit). NORMAL mode: it coincides with the notch exactly (same centre, width,
    // height, top margin), so a panel reads as the island morphing IN PLACE: the
    // notch.fill is its background and morphFill stays hidden. GAME mode: the notch
    // stays a top bar, so this detaches and FLOATS just below it with its own fill +
    // shadow. Single instances live here (no per-mode duplication of stateful panels).
    Item {
        id: morphHost
        anchors.top: parent.top
        // game bar: floats below it. notch: flush. island: its gap. Written as ONE continuous
        // expression off barT/flushT rather than branches + a Behavior, so it never steps.
        anchors.topMargin: (notch.height + Theme.s2) * bar.barT + bar.topGap * (1 - bar.flushT)
        anchors.horizontalCenter: parent.horizontalCenter

        // the height the open panel wants: single source of truth (the notch reads this
        // too when it morphs the panel in place).
        readonly property int contentHeight: bar.polkitWanted ? (polkitContent.implicitHeight + Theme.panelPad * 2)
              : bar.launcherWanted ? (launcher.implicitHeight + launcher.pad * 2)
              : bar.ccWanted ? (controlCenter.implicitHeight + Theme.panelPad * 2)
              : bar.wallpaperWanted ? (wallpaperContent.implicitHeight + Theme.panelPad * 2)
              : bar.logoutWanted ? (logoutContent.implicitHeight + Theme.panelPad * 2)
              : bar.calendarWanted ? (calendarContent.implicitHeight + Theme.panelPad * 2)
              : 0

        // game: own footprint (floats below). normal: ride the notch exactly (seamless
        // in-place morph, the notch is the animated surface and this just follows it).
        width: bar.barForm ? bar.morphW : notch.width
        height: bar.barForm ? contentHeight : notch.height
        Behavior on width  { enabled: bar.barForm; NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
        Behavior on height { enabled: bar.barForm; NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }

        // own background: drawn ONLY in Game Mode (when floating below the bar). In
        // normal mode the notch.fill behind us is the panel's background.
        Rectangle {
            id: morphFill
            anchors.fill: parent
            radius: Theme.rIslandOpen
            color: Theme.base
            border.width: 1
            border.color: Theme.rim
            antialiasing: true
            visible: bar.barForm
            opacity: bar.morphWanted ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
            layer.enabled: Theme.shadows
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Theme.shadow
                shadowBlur: Theme.shadowBlur
                shadowVerticalOffset: Theme.shadowY
                blurMax: Theme.shadowBlurMax
                autoPaddingEnabled: true
            }
        }

        // swallow clicks inside the panel (so they don't reach the click-outside backdrop)
        MouseArea {
            anchors.fill: parent
            enabled: bar.morphWanted
        }

        LauncherContent {
            id: launcher
            // tighter than the other panels: the result rows run nearly edge to edge and
            // carry their own inner padding, the way Raycast's do
            readonly property int pad: Theme.s2 + 2
            anchors.fill: parent
            anchors.margins: pad
            active: bar.launcherWanted
            opacity: bar.launcherWanted ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
        }
        ControlCenterContent {
            id: controlCenter
            anchors.fill: parent
            anchors.margins: Theme.panelPad
            active: bar.ccWanted
            opacity: bar.ccWanted ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
        }
        WallpaperContent {
            id: wallpaperContent
            anchors.fill: parent
            anchors.margins: Theme.panelPad
            active: bar.wallpaperWanted
            opacity: bar.wallpaperWanted ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
        }
        LogoutContent {
            id: logoutContent
            anchors.fill: parent
            anchors.margins: Theme.panelPad
            active: bar.logoutWanted
            opacity: bar.logoutWanted ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
        }
        PolkitContent {
            id: polkitContent
            anchors.fill: parent
            anchors.margins: Theme.panelPad
            active: bar.polkitWanted
            opacity: bar.polkitWanted ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
        }
        CalendarContent {
            id: calendarContent
            anchors.fill: parent
            anchors.margins: Theme.panelPad
            active: bar.calendarWanted
            opacity: bar.calendarWanted ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
        }
    }

}
