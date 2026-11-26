import QtQuick
import QtQuick.Shapes
import "../../theme"
import "../../config"
import "../../components"
import "../controlcenter"
import "../../config/CcLayout.js" as CcLayout

// Drag-and-drop editor for the control center's mosaic, hosted in Settings. It edits the
// REAL layout through Config's cc* API (every call writes config.json, the live panel
// re-renders from Config.ccItems), so what you see here is what the island will show.
//
// The grid is drawn 1:1 with the panel: the canvas is Config.ccContentW wide, so the
// cell size comes out identical to Config.ccCell and the cards are the actual controls
// (CcControl with interactive off) at their actual size. The full row budget is drawn,
// empty rows included, so there's always somewhere to drop. Editing follows the three
// editors people already know: iOS 18's minus badge + corner hook, Tahoe's right-click
// size menu, Android's tidy / undo / remove strip. Selection, drag and menu state all
// live here (local), only the layout itself goes through Config.
Item {
    id: editor

    implicitHeight: col.implicitHeight

    // ── geometry (mirrors Config so the preview matches the panel) ──
    readonly property int cols: Config.ccColumns
    readonly property int maxRows: Config.ccMaxRows
    readonly property int gap: Config.ccGap
    readonly property real canvasW: Math.max(1, Math.min(width, Config.ccContentW))
    readonly property real cell: (canvasW - (cols - 1) * gap) / cols
    readonly property real pitch: cell + gap
    readonly property real canvasH: extent(maxRows)
    function extent(n) { return n * cell + (n - 1) * gap; }
    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

    // ── editor state ──
    property string selectedKey: ""
    property string dragKey: ""        // card being moved
    property string galleryKey: ""     // gallery chip being dragged in
    property string resizeKey: ""      // card whose corner hook is held
    property string lastKey: ""        // last card dropped: stays on top while it settles
    property string menuKey: ""
    property real menuX: 0
    property real menuY: 0
    readonly property bool dragging: dragKey !== "" || galleryKey !== ""

    // pointer, tracked in both spaces while something is being dragged
    property real ptX: 0               // editor coords (for the remove strip / drag image)
    property real ptY: 0
    property real ptCx: 0              // canvas coords (for targeting)
    property real ptCy: 0
    property bool overRemove: false
    property bool overCanvas: false

    // target footprint under a drag: where it lands, and what landing there costs
    property int tx: 0
    property int ty: 0
    property int tw: 1
    property int th: 1
    property string dropKind: ""       // clean | displace | invalid | remove
    property bool targetVisible: false

    // resize preview (the hook drag): snapped candidate footprint
    property int rx: 0
    property int ry: 0
    property int rw: 1
    property int rh: 1

    // The gallery is republished as a fresh array on every layout write; only hand a new one
    // to the Repeater when its membership actually changed, or the chips would rebuild under
    // the pointer on every drop (patterns.md #3).
    property var gallery: []
    property string galleryRaw: ""
    function syncGallery() {
        const raw = Config.ccAvailable.map(r => r.key).join(",");
        if (raw === galleryRaw) return;
        galleryRaw = raw;
        gallery = Config.ccAvailable;
    }
    function defaultSize(key) {
        const r = Config.ccReg(key);
        return r ? CcLayout.resolveSize(r.def, cols) : [1, 1];
    }

    // ── status line: transient messages over a standing hint ──
    property string status: ""
    readonly property string hint: dragKey !== "" && dropKind === "remove" ? "Release to remove"
        : dragging && dropKind === "invalid" && (galleryKey === "" || overCanvas) ? "Doesn't fit here"
        : dragging && dropKind === "displace" && (galleryKey === "" || overCanvas) ? "Will move others"
        : status !== "" ? status
        : "Drag to move · corner to resize · right-click for sizes"
    Timer { id: statusTimer; interval: 2500; onTriggered: editor.status = "" }
    function flash(msg) { status = msg; statusTimer.restart(); }

    property bool resetArmed: false
    Timer { id: resetTimer; interval: 3000; onTriggered: editor.resetArmed = false }

    readonly property var selectedItem: Config.ccItem(selectedKey)
    readonly property var selectedSizes: Config.ccSizesFor(selectedKey)
    readonly property string selectedLabel: { const r = Config.ccReg(selectedKey); return r ? r.label : ""; }

    function select(key) {
        selectedKey = key;
        canvas.forceActiveFocus();
    }
    function openMenu(key, pt) {
        menuLeave.stop();      // a pending close from the last menu must not take this one
        menuKey = key;
        menuX = pt.x;
        menuY = pt.y;
    }
    // step the selected card through its supported sizes ([ and ])
    function stepSize(dir) {
        const it = selectedItem;
        if (!it) return;
        const sizes = selectedSizes;
        let i = sizes.findIndex(s => s[0] === it.w && s[1] === it.h);
        if (i < 0) i = 0;
        i = (i + dir + sizes.length) % sizes.length;
        if (!Config.ccResize(selectedKey, sizes[i][0], sizes[i][1])) flash("Doesn't fit");
    }

    // ── drag targeting, shared by card moves and gallery drops ──
    function trackPointer(cx, cy) {
        ptCx = cx;
        ptCy = cy;
        const e = canvas.mapToItem(editor, cx, cy);
        ptX = e.x;
        ptY = e.y;
        const slack = 20;
        overCanvas = cx >= -slack && cy >= -slack && cx <= canvas.width + slack && cy <= canvas.height + slack;
        if (removeZone.height > 0) {
            const rz = removeZone.mapToItem(editor, 0, 0);
            overRemove = ptX >= rz.x && ptX <= rz.x + removeZone.width && ptY >= rz.y && ptY <= rz.y + removeZone.height;
        } else {
            overRemove = false;
        }
    }
    // (x, y) is the would-be top-left of the footprint in canvas pixels
    function updateTarget(key, x, y, w, h) {
        tw = w;
        th = h;
        tx = clamp(Math.round(x / pitch), 0, cols - w);
        ty = clamp(Math.round(y / pitch), 0, maxRows - h);
        const far = 40;
        const farOut = ptCx < -far || ptCy < -far || ptCx > canvas.width + far || ptCy > canvas.height + far;
        if (dragKey !== "" && (overRemove || farOut)) {
            dropKind = "remove";
            targetVisible = false;
            return;
        }
        if (Config.ccFits(tx, ty, w, h, key)) {
            dropKind = "clean";
        } else {
            // dry-run the displacement so the footprint can warn before the drop refuses
            const need = Config.ccItem(key) ? Config.ccItems.length : Config.ccItems.length + 1;
            const next = CcLayout.place(Config.ccItems, cols, maxRows, key, tx, ty, w, h);
            dropKind = (!next || next.length < need) ? "invalid" : "displace";
        }
        targetVisible = galleryKey === "" || overCanvas;
    }
    // a drag is over however it ended: the ghost and the drop footprint go with it
    function endGalleryDrag() { galleryKey = ""; clearTarget(); }
    function endCardDrag() { dragKey = ""; clearTarget(); }
    function clearTarget() {
        targetVisible = false;
        dropKind = "";
        overRemove = false;
        overCanvas = false;
    }

    CcGridModel { id: grid }
    Component.onCompleted: { grid.sync(Config.ccItems); syncGallery(); }
    Connections {
        target: Config
        function onCcItemsChanged() {
            grid.sync(Config.ccItems);
            editor.syncGallery();
            if (editor.selectedKey !== "" && !Config.ccItem(editor.selectedKey)) editor.selectedKey = "";
            if (editor.menuKey !== "" && !Config.ccItem(editor.menuKey)) editor.menuKey = "";
        }
    }

    // ── shared bits ──

    // flat pill button in the shell's language: surfaceOverlay, a fillLow veil on hover,
    // solid accent (or whatever `activeColor` says) when active
    component ToolButton: Rectangle {
        id: tb
        property string text: ""
        property bool active: false
        property color activeColor: Theme.accent
        signal clicked()
        implicitWidth: tbLabel.implicitWidth + Theme.s3 * 2
        implicitHeight: 28
        radius: Theme.rPill
        color: active ? activeColor : Theme.surfaceOverlay
        opacity: enabled ? 1 : 0.45
        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
        Rectangle { anchors.fill: parent; radius: parent.radius; color: Theme.fillLow; opacity: tbMa.containsMouse && !tb.active ? 1 : 0 }
        StyledText {
            id: tbLabel
            anchors.centerIn: parent
            variant: "label"
            font.weight: Theme.wMedium
            text: tb.text
            color: tb.active ? (Theme.lum(tb.activeColor) > 0.55 ? Theme.base : Theme.foreground) : Theme.inkPrimary
        }
        MouseArea { id: tbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.clicked() }
    }

    // one supported size: a tiny proportional rectangle plus "W×H"; accent when current
    component SizeChip: Rectangle {
        id: chip
        property int cw: 1
        property int ch: 1
        property bool current: false
        signal picked()
        implicitWidth: chipRow.implicitWidth + Theme.s2 * 2 + 2
        implicitHeight: 26
        radius: Theme.rPill
        color: current ? Theme.accent : (chipMa.containsMouse ? Theme.fillHigh : Theme.fillLow)
        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Theme.s1
            Item {
                width: 36; height: 16
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    anchors.centerIn: parent
                    width: chip.cw * 4 - 1
                    height: chip.ch * 4 - 1
                    radius: 1
                    color: chip.current ? Theme.onAccent : Theme.inkDim
                }
            }
            StyledText {
                capCentreIn: parent
                variant: "caption"
                text: chip.cw + "×" + chip.ch
                color: chip.current ? Theme.onAccent : Theme.inkPrimary
            }
        }
        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.picked() }
    }

    Column {
        id: col
        width: parent.width
        spacing: Theme.s3

        // ── toolbar ──
        Item {
            width: parent.width
            height: 28

            Row {
                id: toolRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.s2

                // column count: refused (and the old choice kept) when the layout wouldn't survive
                Rectangle {
                    height: 28
                    width: colRow.implicitWidth + 4
                    radius: Theme.rPill
                    color: Theme.surfaceOverlay
                    anchors.verticalCenter: parent.verticalCenter
                    Row {
                        id: colRow
                        anchors.centerIn: parent
                        spacing: 0
                        Repeater {
                            model: Config.ccMaxColumns - Config.ccMinColumns + 1
                            delegate: Rectangle {
                                id: colBtn
                                required property int index
                                readonly property int n: Config.ccMinColumns + index
                                readonly property bool active: Config.ccColumns === n
                                width: 24; height: 24; radius: 12
                                color: active ? Theme.accent : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                                Rectangle { anchors.fill: parent; radius: 12; color: Theme.fillLow; opacity: colMa.containsMouse && !colBtn.active ? 1 : 0 }
                                StyledText {
                                    anchors.centerIn: parent
                                    variant: "caption"
                                    font.weight: Theme.wMedium
                                    text: colBtn.n
                                    color: colBtn.active ? Theme.onAccent : Theme.inkPrimary
                                }
                                MouseArea {
                                    id: colMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (!Config.ccSetColumns(colBtn.n)) editor.flash("Remove or shrink a control first")
                                }
                            }
                        }
                    }
                }
                ToolButton { text: "Tidy"; anchors.verticalCenter: parent.verticalCenter; onClicked: Config.ccTidy() }
                ToolButton { text: "Undo"; enabled: Config.ccCanUndo; anchors.verticalCenter: parent.verticalCenter; onClicked: Config.ccUndo() }
                ToolButton {
                    // two-step: the first click arms it (in the destructive colour) for 3s
                    text: editor.resetArmed ? "Reset layout?" : "Reset"
                    active: editor.resetArmed
                    activeColor: Theme.bad
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: {
                        if (editor.resetArmed) { editor.resetArmed = false; resetTimer.stop(); Config.ccReset(); }
                        else { editor.resetArmed = true; resetTimer.restart(); }
                    }
                }
            }
            StyledText {
                anchors { left: toolRow.right; leftMargin: Theme.s3; right: parent.right }
                capCentreIn: parent
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                variant: "caption"
                color: editor.dropKind === "invalid" || editor.dropKind === "remove" ? Theme.bad : Theme.inkDim
                text: editor.hint
            }
        }

        // ── canvas ──
        FocusScope {
            id: canvas
            width: editor.canvasW
            height: editor.canvasH
            anchors.horizontalCenter: parent.horizontalCenter

            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Escape) { editor.menuKey = ""; editor.selectedKey = ""; e.accepted = true; return; }
                if (editor.selectedKey === "") return;
                const k = editor.selectedKey;
                let handled = true;
                switch (e.key) {
                case Qt.Key_Left:  if (!Config.ccNudge(k, -1, 0)) editor.flash("Doesn't fit"); break;
                case Qt.Key_Right: if (!Config.ccNudge(k, 1, 0)) editor.flash("Doesn't fit"); break;
                case Qt.Key_Up:    if (!Config.ccNudge(k, 0, -1)) editor.flash("Doesn't fit"); break;
                case Qt.Key_Down:  if (!Config.ccNudge(k, 0, 1)) editor.flash("Doesn't fit"); break;
                case Qt.Key_Delete:
                case Qt.Key_Backspace: Config.ccRemove(k); break;
                case Qt.Key_BracketLeft: editor.stepSize(-1); break;
                case Qt.Key_BracketRight: editor.stepSize(1); break;
                default: handled = false;
                }
                e.accepted = handled;
            }

            // open spots: one faint disc per empty-or-not cell, so the free grid reads as a grid
            Repeater {
                model: editor.cols * editor.maxRows
                delegate: Rectangle {
                    required property int index
                    x: (index % editor.cols) * editor.pitch
                    y: Math.floor(index / editor.cols) * editor.pitch
                    width: editor.cell
                    height: editor.cell
                    radius: editor.cell / 2
                    color: Theme.fillLow
                    opacity: 0.6
                }
            }

            // empty canvas: click deselects and takes keyboard focus
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: { editor.selectedKey = ""; editor.menuKey = ""; canvas.forceActiveFocus(); }
            }

            // where the drag would land, tinted by what landing there means
            Rectangle {
                id: target
                z: 5
                x: editor.tx * editor.pitch
                y: editor.ty * editor.pitch
                width: editor.extent(editor.tw)
                height: editor.extent(editor.th)
                radius: (editor.tw === 1 && editor.th === 1) ? width / 2 : (editor.th >= 2 ? Theme.rXl : height / 2)
                readonly property color tint: editor.dropKind === "clean" ? Theme.accent
                    : editor.dropKind === "invalid" ? Theme.bad
                    : Theme.foreground
                color: editor.dropKind === "displace" ? Theme.fillHigh : Theme.alpha(tint, 0.18)
                border.width: 1
                border.color: Theme.alpha(tint, 0.5)
                opacity: editor.targetVisible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }
                Behavior on x { NumberAnimation { duration: Theme.dur(Theme.dFast); easing.type: Theme.easeOut } }
                Behavior on y { NumberAnimation { duration: Theme.dur(Theme.dFast); easing.type: Theme.easeOut } }
                Behavior on width { NumberAnimation { duration: Theme.dur(Theme.dFast); easing.type: Theme.easeOut } }
                Behavior on height { NumberAnimation { duration: Theme.dur(Theme.dFast); easing.type: Theme.easeOut } }
            }

            // the cards: the real controls, with editor chrome on top
            Repeater {
                model: grid
                delegate: Item {
                    id: card
                    required property string ckey
                    required property int gx
                    required property int gy
                    required property int gw
                    required property int gh

                    readonly property bool selected: editor.selectedKey === ckey
                    readonly property bool live: editor.dragKey === ckey
                    readonly property bool hovered: !editor.dragging && editor.resizeKey === ""
                        && (cardMa.containsMouse || badgeMa.containsMouse || hookMa.containsMouse)
                    readonly property bool chrome: (hovered || selected) && !live
                    readonly property bool resizable: Config.ccSizesFor(ckey).length > 1
                    // the tiles' own shapes: 1×1 is a disc, one row is a capsule, taller is a card
                    readonly property real shapeRadius: (gw === 1 && gh === 1) ? width / 2 : (gh >= 2 ? Theme.rXl : height / 2)
                    // flipped imperatively around a drag so the Behaviors can't catch the
                    // hand-off in either direction (a bound `enabled` races the x binding)
                    property bool animate: true
                    property real dragX: 0
                    property real dragY: 0

                    x: live ? dragX : gx * editor.pitch
                    y: live ? dragY : gy * editor.pitch
                    width: editor.extent(gw)
                    height: editor.extent(gh)
                    z: live ? 10 : (editor.lastKey === ckey ? 6 : (selected ? 2 : 1))
                    scale: live ? 1.03 : 1
                    opacity: live ? 0.92 : 1

                    Behavior on x { enabled: card.animate; NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                    Behavior on y { enabled: card.animate; NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                    Behavior on width { enabled: card.animate; NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                    Behavior on height { enabled: card.animate; NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                    Behavior on scale { NumberAnimation { duration: Theme.dur(Theme.dFast); easing.type: Theme.easeOut } }
                    Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }

                    CcControl {
                        anchors.fill: parent
                        key: card.ckey
                        w: card.gw
                        h: card.gh
                        cell: editor.cell
                        gap: editor.gap
                        interactive: false
                    }

                    // hover outline / selection ring
                    Rectangle {
                        anchors.fill: parent
                        radius: card.shapeRadius
                        color: "transparent"
                        border.width: card.selected ? 2 : 1
                        border.color: card.selected ? Theme.accent : Theme.alpha(Theme.foreground, 0.35)
                        opacity: card.chrome ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }
                    }

                    // move: press, drag past 4px, the card lifts and follows the grab point
                    MouseArea {
                        id: cardMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: card.live ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        property real pressCx: 0
                        property real pressCy: 0
                        property real grabDx: 0
                        property real grabDy: 0
                        onPressed: (m) => {
                            editor.select(card.ckey);
                            if (m.button !== Qt.LeftButton) return;
                            editor.menuKey = "";
                            const p = mapToItem(canvas, m.x, m.y);
                            pressCx = p.x; pressCy = p.y;
                            grabDx = p.x - card.x; grabDy = p.y - card.y;
                        }
                        onPositionChanged: (m) => {
                            if (!(pressedButtons & Qt.LeftButton)) return;
                            const p = mapToItem(canvas, m.x, m.y);
                            if (!card.live) {
                                if (Math.hypot(p.x - pressCx, p.y - pressCy) < 4) return;
                                card.animate = false;
                                card.dragX = card.x;
                                card.dragY = card.y;
                                editor.dragKey = card.ckey;
                            }
                            card.dragX = p.x - grabDx;
                            card.dragY = p.y - grabDy;
                            editor.trackPointer(p.x, p.y);
                            editor.updateTarget(card.ckey, card.dragX, card.dragY, card.gw, card.gh);
                        }
                        onReleased: (m) => {
                            if (m.button !== Qt.LeftButton || !card.live) return;
                            const kind = editor.dropKind;
                            editor.lastKey = card.ckey;
                            card.animate = true;
                            if (kind === "remove") {
                                // this one takes the card off the grid and destroys the delegate,
                                // so the drag state goes first (see the gallery chip)
                                const k = card.ckey;
                                editor.endCardDrag();
                                Config.ccRemove(k);
                                return;
                            }
                            if (kind === "invalid" || !Config.ccPlace(card.ckey, editor.tx, editor.ty, card.gw, card.gh)) {
                                editor.flash("Doesn't fit");
                            }
                            // Config has already moved the model row, so dropping `live` lands
                            // the card on its new cell through the (re-enabled) spring
                            editor.endCardDrag();
                        }
                        onCanceled: if (card.live) editor.endCardDrag()
                        Component.onDestruction: if (editor.dragKey === card.ckey) editor.endCardDrag()
                        onClicked: (m) => {
                            if (m.button === Qt.RightButton) editor.openMenu(card.ckey, mapToItem(editor, m.x, m.y));
                        }
                    }

                    // iOS minus badge, top-left, poking past the corner
                    Rectangle {
                        id: badge
                        x: -8; y: -8
                        width: 20; height: 20; radius: 10
                        color: Theme.bad
                        opacity: card.chrome ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 10; height: 2; radius: 1
                            color: Theme.lum(Theme.bad) > 0.55 ? Theme.base : Theme.foreground
                        }
                        MouseArea {
                            id: badgeMa
                            anchors.fill: parent
                            anchors.margins: -2
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Config.ccRemove(card.ckey)
                        }
                    }

                    // iOS corner hook, bottom-right: only when the control has more than one size
                    Item {
                        id: hook
                        width: 24; height: 24
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        opacity: card.chrome && card.resizable ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }
                        Shape {
                            anchors.fill: parent
                            antialiasing: true
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeColor: Theme.accent
                                strokeWidth: 3
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                PathAngleArc { centerX: 6; centerY: 6; radiusX: 12; radiusY: 12; startAngle: 5; sweepAngle: 80 }
                            }
                        }
                        MouseArea {
                            id: hookMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.SizeFDiagCursor
                            onPressed: (m) => {
                                editor.select(card.ckey);
                                editor.menuKey = "";
                                editor.resizeKey = card.ckey;
                                editor.rx = card.gx; editor.ry = card.gy;
                                editor.rw = card.gw; editor.rh = card.gh;
                            }
                            onPositionChanged: (m) => {
                                if (!pressed) return;
                                const p = mapToItem(canvas, m.x, m.y);
                                const cw = Math.max(1, Math.round((p.x - card.x + editor.gap) / editor.pitch));
                                const ch = Math.max(1, Math.round((p.y - card.y + editor.gap) / editor.pitch));
                                const s = Config.ccSnapSize(card.ckey, cw, ch);
                                editor.rw = s[0]; editor.rh = s[1];
                                editor.rx = Math.min(card.gx, editor.cols - s[0]);
                                editor.ry = Math.min(card.gy, editor.maxRows - s[1]);
                            }
                            onReleased: {
                                if (editor.resizeKey !== card.ckey) return;
                                if (editor.rw !== card.gw || editor.rh !== card.gh) {
                                    if (!Config.ccResize(card.ckey, editor.rw, editor.rh)) editor.flash("Doesn't fit");
                                }
                                editor.resizeKey = "";
                            }
                        }
                    }
                }
            }

            // resize preview: the snapped candidate footprint, outlined over everything
            Rectangle {
                z: 20
                visible: editor.resizeKey !== ""
                x: editor.rx * editor.pitch
                y: editor.ry * editor.pitch
                width: editor.extent(editor.rw)
                height: editor.extent(editor.rh)
                radius: (editor.rw === 1 && editor.rh === 1) ? width / 2 : (editor.rh >= 2 ? Theme.rXl : height / 2)
                color: Theme.alpha(Theme.accent, 0.08)
                border.width: 2
                border.color: Theme.alpha(Theme.accent, 0.8)
                Behavior on x { NumberAnimation { duration: Theme.dur(Theme.dFast); easing.type: Theme.easeOut } }
                Behavior on y { NumberAnimation { duration: Theme.dur(Theme.dFast); easing.type: Theme.easeOut } }
                Behavior on width { NumberAnimation { duration: Theme.dur(Theme.dFast); easing.type: Theme.easeOut } }
                Behavior on height { NumberAnimation { duration: Theme.dur(Theme.dFast); easing.type: Theme.easeOut } }
            }
        }

        // ── inspector: the selected control's name, size, and its size chips ──
        Item {
            width: parent.width
            visible: editor.selectedItem !== null && !editor.dragging
            implicitHeight: visible ? Math.max(inspectorLabel.implicitHeight, inspectorFlow.implicitHeight) : 0
            StyledText {
                id: inspectorLabel
                anchors.left: parent.left
                anchors.top: parent.top
                height: 26
                variant: "label"
                font.weight: Theme.wMedium
                color: Theme.inkPrimary
                text: editor.selectedItem
                    ? editor.selectedLabel + " · " + editor.selectedItem.w + "×" + editor.selectedItem.h
                    : ""
            }
            Flow {
                id: inspectorFlow
                anchors { left: inspectorLabel.right; leftMargin: Theme.s3; right: parent.right; top: parent.top }
                spacing: Theme.s1
                Repeater {
                    model: editor.selectedSizes
                    delegate: SizeChip {
                        required property var modelData
                        cw: modelData[0]
                        ch: modelData[1]
                        current: editor.selectedItem !== null && editor.selectedItem.w === cw && editor.selectedItem.h === ch
                        onPicked: if (!Config.ccResize(editor.selectedKey, cw, ch)) editor.flash("Doesn't fit")
                    }
                }
            }
        }

        // ── remove strip (Android): only around while something is being dragged ──
        Item {
            id: removeZone
            width: parent.width
            height: editor.dragKey !== "" ? 44 : 0
            clip: true
            Behavior on height { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
            readonly property color tint: editor.overRemove ? Theme.bad : Theme.inkFaint
            Rectangle {
                anchors.fill: parent
                radius: Theme.rMd
                color: editor.overRemove ? Theme.alpha(Theme.bad, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
            }
            Shape {
                id: dash
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                readonly property real r: Theme.rMd
                ShapePath {
                    strokeColor: removeZone.tint
                    strokeWidth: 1
                    fillColor: "transparent"
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [4, 3]
                    startX: dash.r; startY: 0.5
                    PathLine { x: dash.width - dash.r; y: 0.5 }
                    PathArc { x: dash.width - 0.5; y: dash.r; radiusX: dash.r; radiusY: dash.r }
                    PathLine { x: dash.width - 0.5; y: dash.height - dash.r }
                    PathArc { x: dash.width - dash.r; y: dash.height - 0.5; radiusX: dash.r; radiusY: dash.r }
                    PathLine { x: dash.r; y: dash.height - 0.5 }
                    PathArc { x: 0.5; y: dash.height - dash.r; radiusX: dash.r; radiusY: dash.r }
                    PathLine { x: 0.5; y: dash.r }
                    PathArc { x: dash.r; y: 0.5; radiusX: dash.r; radiusY: dash.r }
                }
            }
            StyledText {
                anchors.centerIn: parent
                variant: "label"
                color: editor.overRemove ? Theme.bad : Theme.inkDim
                text: "Drag here to remove"
            }
        }

        // ── gallery: everything not yet placed ──
        StyledText { variant: "caption"; color: Theme.inkFaint; text: "Add a control" }
        StyledText {
            visible: editor.gallery.length === 0
            variant: "label"
            color: Theme.inkFaint
            text: "Everything is placed"
        }
        Flow {
            width: parent.width
            spacing: Theme.s2
            visible: editor.gallery.length > 0
            Repeater {
                model: editor.gallery
                delegate: Rectangle {
                    id: gchip
                    required property var modelData
                    readonly property string key: modelData.key
                    readonly property var def: editor.defaultSize(key)
                    readonly property bool live: editor.galleryKey === key
                    implicitWidth: gRow.implicitWidth + Theme.s3 * 2
                    implicitHeight: 36
                    radius: Theme.rPill
                    color: Theme.surfaceOverlay
                    opacity: live ? 0.4 : 1
                    Rectangle { anchors.fill: parent; radius: parent.radius; color: Theme.fillLow; opacity: gMa.containsMouse && !gchip.live ? 1 : 0 }
                    Row {
                        id: gRow
                        anchors.centerIn: parent
                        spacing: Theme.s2
                        Item {
                            width: 22; height: 18
                            anchors.verticalCenter: parent.verticalCenter
                            // Wi-Fi has no path icon: its meter component stands in
                            WifiIcon { anchors.centerIn: parent; visible: gchip.key === "wifi"; strength: 1; active: true; color: Theme.inkPrimary }
                            Icon { anchors.centerIn: parent; visible: gchip.key !== "wifi"; name: gchip.modelData.icon; size: 18 }
                        }
                        StyledText { capCentreIn: parent; variant: "label"; text: gchip.modelData.label; color: Theme.inkPrimary }
                        StyledText { capCentreIn: parent; variant: "caption"; text: gchip.def[0] + "×" + gchip.def[1]; color: Theme.inkDim }
                    }
                    // click adds at the first free spot; a drag carries it onto the canvas
                    MouseArea {
                        id: gMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        property real pressX: 0
                        property real pressY: 0
                        property bool moved: false
                        onPressed: (m) => { pressX = m.x; pressY = m.y; moved = false; editor.menuKey = ""; }
                        onPositionChanged: (m) => {
                            if (!pressed) return;
                            if (!moved) {
                                if (Math.hypot(m.x - pressX, m.y - pressY) < 4) return;
                                moved = true;
                                editor.galleryKey = gchip.key;
                            }
                            const p = mapToItem(canvas, m.x, m.y);
                            editor.trackPointer(p.x, p.y);
                            const w = gchip.def[0], h = gchip.def[1];
                            editor.updateTarget(gchip.key, p.x - editor.extent(w) / 2, p.y - editor.extent(h) / 2, w, h);
                        }
                        // The ghost hangs on editor.galleryKey and ONLY this chip clears it, so every
                        // way the drag can end has to. A release that lands the control takes the
                        // chip out of the gallery and destroys this delegate, so the drag state is
                        // dropped BEFORE the model changes (and `canceled`/destruction cover a lost
                        // grab and a gallery rebuilt under the pointer). Miss one and the ghost is
                        // stranded over the grid looking like a tooltip that will not go away.
                        onReleased: {
                            if (!moved) return;
                            const k = gchip.key, over = editor.overCanvas, kind = editor.dropKind;
                            const tx = editor.tx, ty = editor.ty;
                            editor.endGalleryDrag();
                            if (over && kind !== "invalid") {
                                if (!Config.ccAdd(k, tx, ty)) editor.flash("No room");
                            } else if (over) {
                                editor.flash("Doesn't fit");
                            }
                        }
                        onCanceled: editor.endGalleryDrag()
                        Component.onDestruction: if (editor.galleryKey === gchip.key) editor.endGalleryDrag()
                        onClicked: if (!moved && !Config.ccAdd(gchip.key)) editor.flash("No room")
                    }
                }
            }
        }
    }

    // the chip's translucent drag image, following the pointer (HIG: a drag image, not the chip)
    Rectangle {
        z: 60
        visible: editor.galleryKey !== ""
        x: editor.ptX - width / 2
        y: editor.ptY - height / 2
        implicitWidth: dragLabel.implicitWidth + Theme.s4 * 2
        implicitHeight: 36
        radius: Theme.rPill
        color: Theme.surfaceOverlay
        border.width: 1
        border.color: Theme.hairline
        opacity: 0.92
        StyledText {
            id: dragLabel
            anchors.centerIn: parent
            variant: "label"
            color: Theme.inkPrimary
            text: { const r = Config.ccReg(editor.galleryKey); return r ? r.label : ""; }
        }
    }

    // ── right-click size menu (Tahoe): chips for every supported size, then Remove ──
    Item {
        id: menuLayer
        anchors.fill: parent
        z: 50
        visible: editor.menuKey !== ""
        readonly property var sizes: Config.ccSizesFor(editor.menuKey)
        readonly property var cur: Config.ccItem(editor.menuKey)

        // Anything outside the menu dismisses it, and so does simply walking away from it.
        // A context menu that only a click can close sits over the grid looking like a
        // tooltip that will not go away, and it eats the next click you meant for a card.
        // hoverEnabled here also freezes the cards' hover chrome while the menu is up,
        // which is what a menu should do; the grace margin and the delay keep it alive
        // while the pointer crosses the gap between the card and the menu.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onPressed: editor.menuKey = ""
            onPositionChanged: (m) => {
                const g = 28;
                const near = m.x >= menuBox.x - g && m.x <= menuBox.x + menuBox.width + g
                          && m.y >= menuBox.y - g && m.y <= menuBox.y + menuBox.height + g;
                if (near) menuLeave.stop(); else menuLeave.restart();
            }
            onExited: menuLeave.restart()
        }
        Timer { id: menuLeave; interval: 260; onTriggered: editor.menuKey = "" }

        Rectangle {
            id: menuBox
            x: editor.clamp(editor.menuX, 0, editor.width - width)
            y: editor.clamp(editor.menuY, 0, editor.height - height)
            width: 200
            implicitHeight: menuCol.implicitHeight + Theme.s2 * 2
            radius: Theme.rMd
            color: Theme.surfaceOverlay
            border.width: 1
            border.color: Theme.hairline
            Column {
                id: menuCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.s2 }
                spacing: Theme.s2
                StyledText {
                    variant: "caption"
                    color: Theme.inkFaint
                    text: { const r = Config.ccReg(editor.menuKey); return r ? r.label.toUpperCase() : ""; }
                }
                Flow {
                    width: parent.width
                    spacing: Theme.s1
                    Repeater {
                        model: menuLayer.sizes
                        delegate: SizeChip {
                            required property var modelData
                            cw: modelData[0]
                            ch: modelData[1]
                            current: menuLayer.cur !== null && menuLayer.cur.w === cw && menuLayer.cur.h === ch
                            onPicked: {
                                const k = editor.menuKey;
                                editor.menuKey = "";
                                if (!Config.ccResize(k, cw, ch)) editor.flash("Doesn't fit");
                            }
                        }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: Theme.hairline }
                Rectangle {
                    width: parent.width
                    height: 28
                    radius: Theme.rSm
                    color: rmMa.containsMouse ? Theme.alpha(Theme.bad, 0.12) : "transparent"
                    StyledText {
                        anchors { left: parent.left; leftMargin: Theme.s2 }
                        capCentreIn: parent
                        variant: "label"
                        color: Theme.bad
                        text: "Remove"
                    }
                    MouseArea {
                        id: rmMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { const k = editor.menuKey; editor.menuKey = ""; Config.ccRemove(k); }
                    }
                }
            }
        }
    }
}
