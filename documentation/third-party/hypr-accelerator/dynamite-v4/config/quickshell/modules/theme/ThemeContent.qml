import QtQuick
import Quickshell
import "../../theme"
import "../../config"
import "../../services"
import "../../components"

// Theme switcher that lives INSIDE the bar island (the island morphs into it, see
// Bar.qml). LANDSCAPE: one horizontal row of wide preview cards rather than a tall grid,
// so the panel stays short and picking a colour doesn't swallow the screen.
//
// Each card is an actual preview of the scheme drawn IN the scheme — its background, a
// mock of the island wearing its accent, its six hues, and its name in its own
// foreground. You can tell schemes apart at a glance instead of reading names.
//
// Driven from the keyboard the same way the launcher is: type to filter, arrows to move,
// Enter to apply; hovering only previews (click selects). Same mark language as
// the wallpaper carousel — the RING is the candidate, the DOT is what's live right now.
Item {
    id: root

    property bool active: false
    implicitHeight: col.implicitHeight
    clip: true

    property string query: ""
    property int index: 0
    onIndexChanged: strip.go(index)   // every selection change is one spring from where the strip is

    // Landscape cards, four across, sized off the panel's SETTLED width rather than its
    // live one. Both matter:
    //   · fixed count, so the strip can't reflow mid-morph and drag the selected card out
    //     from under the ring;
    //   · fixed SIZE, because the card height feeds implicitHeight, which is what the island
    //     animates its height toward. Read from the animating width, the island could only
    //     learn how tall to be after it had finished getting wide — so it expanded outward
    //     first and then downward, in two beats instead of one motion. Off a constant, the
    //     final height is known on the first frame and both axes travel together.
    // The strip is still only as wide as the panel, so during the morph the cards are simply
    // revealed rather than resized.
    readonly property int perView: 4
    readonly property int panelW: Math.max(240, Config.themeSwitcherWidth - Theme.s4 * 2)
    readonly property int cardW: Math.floor(panelW / perView)
    readonly property int cardH: Math.round(cardW * 0.50)
    // How far the selected card rises, and the headroom the strip reserves for it. The lift
    // AND the 1.07 swell both push the picked card past its own bounds, and the strip clips
    // horizontally (it has to), so without room set aside the top of the selected card — and
    // its ring — got sliced off. The row is cardH + 2*cardPad tall and the card sits centred
    // in it, so the whole animation happens INSIDE the clip instead of fighting it.
    readonly property int liftPx: 9
    readonly property int cardPad: 14
    readonly property int rowH: cardH + cardPad * 2

    // Matches are RANKED, not just filtered. A plain substring filter kept the list in its
    // alphabetical order, so a single character put the wrong theme first: "n" matches
    // "anime" and "kanagawa" as well as "nightfox"/"noir"/"nord", and alphabetically the
    // incidental matches win. It only looked right once you'd typed enough to leave one
    // survivor. Now: names that START with what you typed come first, then the rest ordered
    // by how early the match lands, alphabetical within each tier.
    readonly property var shown: {
        const all = Themes.list ?? [];
        const q = query.trim().toLowerCase();
        if (q === "") return all;
        const hits = [];
        for (let i = 0; i < all.length; i++) {
            const n = (all[i].name ?? "").toLowerCase();
            const at = n.indexOf(q);
            if (at < 0) continue;
            hits.push({ t: all[i], at: at, n: n });
        }
        hits.sort((a, b) => a.at - b.at || a.n.localeCompare(b.n));
        return hits.map(h => h.t);
    }
    readonly property int count: shown.length

    function close() { GlobalState.themeSwitcherOpen = false; }

    function apply(name) {
        // DON'T set Config.theme here. theme-apply.sh is the single writer of config.json:
        // it sets both the theme AND this theme's wallpaper. If we also touch Config, the
        // shell serializes the WHOLE config (with the OLD wallpaper still in it) and that
        // write races the script's, so the wallpaper sometimes gets stomped back to the old
        // one. We just kick off the script; the FileView reload pulls in theme + wallpaper.
        Quickshell.execDetached(["bash", `${Quickshell.env("HOME")}/.config/wallust/theme-apply.sh`, name]);
    }
    function activate() {
        if (root.count === 0) return;
        const t = root.shown[Math.max(0, Math.min(root.index, root.count - 1))];
        if (t) root.apply(t.name);
    }

    // step, or rubber-band at either end (same feel as the wallpaper carousel)
    function step(dir) {
        if (root.count === 0) return;
        const next = root.index + dir;
        root.touched = true;
        if (next < 0 || next >= root.count) { strip.kick(dir); return; }
        root.index = next;
    }

    // Open sitting on whatever's applied, so Enter alone is a no-op instead of a surprise.
    function syncToCurrent() {
        let found = 0;
        for (let i = 0; i < root.count; i++) {
            if (root.shown[i].name === Config.theme) { found = i; break; }
        }
        root.index = found;
        strip.jump(found);
    }

    // True while the island is still morphing open: the strip is being laid out and centred
    // across those frames, so the ring gets PLACED rather than animated into position (a
    // colour tween in flight rides a recycled delegate onto a card it never belonged to).
    property bool opening: false
    // set by the first step after an open: from then on the strip is the user's, and the
    // per-frame recentre of the open morph stands aside so the step's animation survives
    property bool touched: false
    Timer { id: openSettle; interval: Theme.dur(Theme.dSpring) + 60; onTriggered: root.opening = false }

    onActiveChanged: {
        if (active) {
            Themes.refresh();
            field.text = "";      // the box kept its old text across opens; clear it with the query
            query = "";
            lastFilterAt = 0;
            // synchronously, BEFORE the first frame — deferred, the strip painted a frame
            // sitting on index 0 and only then jumped, dragging the ring across the panel
            opening = true;
            touched = false;
            openSettle.restart();
            syncToCurrent();
            Qt.callLater(() => field.forceActiveFocus());
        } else {
            opening = false;
            openSettle.stop();
        }
    }
    // Changing the query hands the ListView a brand-new array, so it tears every delegate
    // down and builds fresh ones — which is why results used to just blink into place. The
    // cards animate their own entry (see the delegate), and this flag is what tells them the
    // rebuild came from a SEARCH rather than from scrolling a new card into view, so plain
    // navigation doesn't set everything fading.
    property bool filtering: false
    Timer { id: filterSettle; interval: Theme.dur(Theme.dEffects) + 220; onTriggered: root.filtering = false }
    property double lastFilterAt: 0
    onQueryChanged: {
        index = 0;
        // Animate the cards in only when this is a SETTLED change. Every keystroke replaces
        // the model, which rebuilds every delegate, and the entry fade runs ~500ms — type
        // faster than that and each fresh card restarts at zero opacity, so the strip just
        // goes blank for as long as you keep typing. Changes arriving in quick succession
        // skip the animation and appear instantly, which is what you want mid-search anyway:
        // you're scanning results, not watching them land.
        const now = Date.now();
        filtering = (now - lastFilterAt) > 260;
        lastFilterAt = now;
        filterSettle.restart();
        // the model is REPLACED here, so whatever the strip was scrolled to is meaningless
        // afterwards; put it on the first result outright rather than sliding to it
        Qt.callLater(() => strip.jump(0));
    }
    // A normal index change is `strip.go(index)`: one spring from wherever the strip is.
    // Only the open and a filter reset place the strip outright (`strip.jump`).

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.s3

        // search row — doubles as the header, same idiom as the launcher
        Item {
            id: searchBar
            width: parent.width
            height: Theme.s6

            Icon {
                id: glass
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                color: Theme.inkDim
            }

            TextInput {
                id: field
                anchors.left: glass.right
                anchors.leftMargin: Theme.s3
                anchors.right: countLabel.left
                anchors.rightMargin: Theme.s2
                anchors.verticalCenter: parent.verticalCenter
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Theme.inkPrimary
                selectionColor: Theme.alpha(Theme.accent, 0.4)
                font.family: Theme.fontBody
                font.pixelSize: Theme.fsBody

                onTextChanged: root.query = text

                // the field keeps focus the whole time so you can keep typing; it just
                // forwards the navigation keys to the strip
                onAccepted: root.activate()
                Keys.onEscapePressed: root.close()
                Keys.onReleased: event => { if (!event.isAutoRepeat && (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Up || event.key === Qt.Key_Down || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) strip.release(); }
                Keys.onLeftPressed: root.step(-1)
                Keys.onRightPressed: root.step(1)
                Keys.onUpPressed: root.step(-root.perView)     // a screenful — it's one row now
                Keys.onDownPressed: root.step(root.perView)
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Home) { root.index = 0; event.accepted = true; }
                    else if (event.key === Qt.Key_End) { root.index = Math.max(0, root.count - 1); event.accepted = true; }
                    else if (event.key === Qt.Key_Tab) { root.step(1); event.accepted = true; }
                    else if (event.key === Qt.Key_Backtab) { root.step(-1); event.accepted = true; }
                }

                StyledText {
                    capCentreIn: parent
                    visible: field.text.length === 0
                    variant: "body"
                    color: Theme.inkFaint
                    text: "Search themes…"
                }
            }

            StyledText {
                id: countLabel
                anchors.right: parent.right
                capCentreIn: parent
                variant: "caption"
                color: Theme.inkFaint
                text: root.count > 0 ? `${root.index + 1}/${root.count}` : ""
            }
        }

        // the landscape strip
        Item {
            width: parent.width
            height: root.rowH

            ListView {
                id: strip
                // SETTLED width, centred, from frame one: the root clip reveals it as the
                // island grows. A strip that filled the growing parent was resized every frame
                // of the morph, and a ListView under StrictlyEnforceRange re-places itself
                // INSTANTLY on every resize, so a step made during the open snapped instead
                // of animating, and the open itself needed a per-frame recentre.
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.panelW
                orientation: ListView.Horizontal
                model: root.shown
                currentIndex: root.index
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
                readonly property real pitch: root.cardW + spacing
                readonly property real centreOff: (width - root.cardW) / 2
                function xFor(i) { return i * pitch - centreOff; }
                function nearest() { return Math.max(0, Math.min(count - 1, Math.round((contentX + centreOff) / pitch))); }
                function go(i) { scroll.stop(); if (count === 0) return; scroll.from = contentX; scroll.to = xFor(i); scroll.start(); }
                function jump(i) { scroll.stop(); if (count === 0) return; contentX = xFor(i); }
                // a full card of travel per step: the island's longer entrance timing, not the
                // base spring, or the strip reads as snapping between cards
                NumberAnimation { id: scroll; target: strip; property: "contentX"; duration: Theme.dur(Theme.dEnter); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
                onDragStarted: scroll.stop()
                onMovementEnded: { const n = nearest(); if (n === root.index) go(n); else root.index = n; }
                // Room at both ends so the FIRST and LAST items can actually reach the centre.
                leftMargin: Math.max(0, (width - root.cardW) / 2)
                rightMargin: Math.max(0, (width - root.cardW) / 2)
                boundsBehavior: Flickable.DragOverBounds
                boundsMovement: Flickable.FollowBoundsBehavior
                // the panel is still growing while it morphs open, so a centre computed a
                // frame ago is wrong once there's more room — re-assert until it settles

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
                    required property var modelData

                    width: root.cardW
                    height: root.rowH

                    readonly property bool live: modelData.name === Config.theme
                    readonly property bool picked: index === root.index
                    // distance from the viewport centre in CARD units, read off the live
                    // contentX so the falloff tracks a drag continuously instead of stepping
                    readonly property real dist: Math.abs((x + width / 2) - (strip.contentX + strip.width / 2)) / Math.max(1, root.cardW)

                    // Depth here is opacity ONLY — deliberately never scale. These cards
                    // carry a label, and text inside a scaled item gets rasterised once at its
                    // natural size and then stretched, so it can't honour hinting or subpixel
                    // AA however it's rendered. Holding every card at scale 1 is what lets the
                    // names go through fontconfig and stay crisp. The falloff is un-animated so
                    // it tracks a drag frame for frame; selection reads through the lift, the
                    // ring, and the weight change instead of a swell.
                    // 0 while the card is arriving, 1 once it's in. Only animated when the
                    // rebuild came from a search; otherwise it starts settled so scrolling
                    // doesn't make cards fade in as they're recycled into view.
                    property real entry: 1
                    Component.onCompleted: if (root.filtering) { entry = 0; entryAnim.start(); }
                    SequentialAnimation {
                        id: entryAnim
                        // cascade outward from the middle of the strip, so results read as
                        // landing rather than all snapping in together
                        PauseAnimation { duration: Theme.dur(Math.min(4, Math.abs(cell.index - root.index)) * 45) }
                        NumberAnimation {
                            target: cell; property: "entry"; to: 1
                            duration: Theme.dur(Theme.dSpring)
                            easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier
                        }
                    }

                    opacity: (1 - Math.min(0.55, dist * 0.3)) * cell.entry
                    // first Translate: rises as it takes the selection, and nudges up under
                    // the pointer. second: the entry drop, kept separate so its animation and
                    // the lift's Behavior don't fight over one value.
                    transform: [
                        Translate {
                            y: cell.picked ? -root.liftPx : (cellMa.containsMouse ? -3 : 0)
                            Behavior on y { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                        },
                        Translate { y: (1 - cell.entry) * 14 }
                    ]

                    // the preview: the scheme drawn in its own colours
                    Rectangle {
                        id: card
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Theme.s1 * 2
                        height: root.cardH
                        radius: Theme.rMd
                        color: cell.modelData.bg || Theme.base
                        clip: true

                        // the six hues — what actually distinguishes one scheme from another
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            // sits just above centre so the name below balances it
                            anchors.verticalCenterOffset: -Math.round(card.height * 0.08)
                            spacing: Math.max(3, Math.round(card.width * 0.022))

                            Repeater {
                                model: cell.modelData.palette ?? []
                                Rectangle {
                                    required property var modelData
                                    width: Math.max(7, Math.round(card.width * 0.075))
                                    height: width
                                    radius: width / 2
                                    color: modelData
                                }
                            }
                        }

                        // name, in the scheme's own foreground — legible on its own background
                        // by construction, since that's the pairing the scheme ships
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Math.round(card.height * 0.10)
                            width: parent.width - Theme.s3 * 2
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            variant: "caption"
                            // no renderType override: inherits StyledText's NativeRendering,
                            // which is the only path that honours fontconfig (hintslight +
                            // rgb subpixel here). Safe now that nothing scales the card.
                            font.weight: cell.picked ? Theme.wMedium : Theme.wRegular
                            text: cell.modelData.name
                            color: cell.modelData.fg || Theme.inkPrimary
                        }
                    }

                    // ring = candidate. Drawn OUTSIDE the clipped card so it never gets cut.
                    Rectangle {
                        anchors.fill: card
                        radius: card.radius
                        color: "transparent"
                        // hover needs to be clearly brighter than idle — hairline (0.14) against
                        // idle (0.10) was a difference you couldn't actually see
                        border.color: cell.picked ? Theme.accent
                                    : cellMa.containsMouse ? Theme.alpha(Theme.foreground, 0.45)
                                    : Theme.alpha(Theme.foreground, 0.10)
                        border.width: cell.picked ? 2 : 1
                        // never while opening: a tween in flight rides a recycled delegate
                        // onto a card it never belonged to
                        Behavior on border.color { enabled: !root.opening; ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                    }

                    // dot = live right now
                    Rectangle {
                        anchors.top: card.top
                        anchors.right: card.right
                        anchors.margins: Theme.s2
                        width: 8; height: 8
                        radius: 4
                        visible: cell.live
                        color: cell.modelData.accent || Theme.accent
                        border.width: 1
                        border.color: Theme.alpha(Theme.base, 0.45)
                    }

                    MouseArea {
                        id: cellMa
                        anchors.fill: card
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Hover only lights the ring, it does NOT move the selection. In a
                        // centred carousel that was a feedback loop: hovering a card recentred
                        // it, which scrolled the strip out from under the pointer, which
                        // hovered a different card, which recentred again — the cursor could
                        // never settle on anything. Click is what selects.
                        onClicked: {
                            if (cell.picked) root.apply(cell.modelData.name);
                            else root.index = cell.index;
                        }
                    }
                }
            }

            // wheel steps the strip. NoButton so it never eats the cards' clicks.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y;
                    if (d !== 0) root.step(d < 0 ? 1 : -1);
                }
            }
        }

        // footer: empty state on the left, the commit hint on the right
        Item {
            width: parent.width
            height: 18

            StyledText {
                anchors.left: parent.left
                capCentreIn: parent
                variant: "caption"
                color: Theme.inkFaint
                visible: root.count === 0
                text: (Themes.list?.length ?? 0) === 0 ? "No colorschemes found" : "No themes match"
            }
            StyledText {
                anchors.right: parent.right
                capCentreIn: parent
                variant: "caption"
                color: Theme.inkFaint
                visible: root.count > 0
                text: "Enter to apply"
            }
        }
    }
}
