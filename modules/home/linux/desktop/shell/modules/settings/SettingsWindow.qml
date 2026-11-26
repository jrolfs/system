import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../config"
import "../../components"

// Settings as its OWN floating desktop window (not an island morph anymore). Two panes,
// modelled on macOS System Settings: a sidebar (search + category list with tinted icons)
// on the left, a detail pane (back/forward, a header block, then grouped rows) on the
// right. No title-bar buttons by request. It's a real toplevel, so on Hyprland add a float
// windowrule for it (title "Settings") so it doesn't tile. Backed by Config like before.
FloatingWindow {
    id: win

    implicitWidth: 860
    implicitHeight: 580
    minimumSize: Qt.size(720, 480)
    // Glass like the island: a translucent pane over a blurred desktop. Hyprland rounds and
    // borders the toplevel itself, so the pane is a plain fill and the region a rectangle.
    color: Theme.base
    title: "Settings"
    BackgroundEffect.blurRegion: Theme.blur ? blurShape : null
    readonly property Region blurShape: Region { item: win.contentItem }

    // shown while GlobalState.settingsOpen; Esc / the toggle shortcut clear that state
    visible: GlobalState.settingsOpen

    property int currentIndex: 0
    property string filter: ""

    // sidebar categories: each maps to a page of the existing settings. `c` is the tint for
    // the little rounded icon, `glyph` a Material Symbols Rounded ligature name (the font
    // shapes the name text into its icon), `desc` the header blurb.
    readonly property var cats: [
        { key: "bar",        label: "Bar & Island",   glyph: "web_asset",        c: "#3b82f6", desc: "Shape and size of the island, the notch, and the Game Mode bar." },
        { key: "media",      label: "Media",          glyph: "music_note",       c: "#e0457b", desc: "The now-playing card inside the expanded island." },
        { key: "clock",      label: "Clock & Date",   glyph: "schedule",         c: "#f2a33c", desc: "Time format, what sits beside the clock, and the calendar." },
        { key: "appearance", label: "Appearance",     glyph: "palette",          c: "#7c6cf0", desc: "Wallpaper, glass, fonts, corners, and surface depth." },
        { key: "motion",     label: "Motion",         glyph: "animation",        c: "#22b8cf", desc: "How fast the shell animates, or whether it animates at all." },
        { key: "launcher",   label: "Launcher",       glyph: "search",           c: "#2fb463", desc: "Size of the app launcher and its result rows." },
        { key: "notif",      label: "Notifications",  glyph: "notifications",    c: "#ef4444", desc: "How long popups stay up and how much they show." },
        { key: "cc",         label: "Control Center", glyph: "tune",             c: "#14b8a6", desc: "Arrange, resize, add and remove the controls." },
        { key: "lock",       label: "Lock Screen",    glyph: "lock",             c: "#8b5cf6", desc: "Blur, dimming, and the password field." },
        { key: "system",     label: "System",         glyph: "settings",         c: "#94a3b8", desc: "Key steps, thresholds, and hardware polling." }
    ]
    readonly property var cat: cats[currentIndex]

    // Openers can ask for a page (GlobalState.settingsPage, e.g. the control center's
    // "edit layout" button). Consumed on open so a later plain toggle lands wherever the
    // user left off, not back on that page.
    Connections {
        target: GlobalState
        function onSettingsOpenChanged() {
            if (GlobalState.settingsOpen && GlobalState.settingsPage !== "") {
                const i = win.cats.findIndex(c => c.key === GlobalState.settingsPage);
                if (i >= 0) win.currentIndex = i;
                GlobalState.settingsPage = "";
            }
        }
    }

    // ── reusable grouped-row bits (a card is just a rounded surfacePanel wrapping these) ──

    // label left, live value right, full-width slider below. `first` drops the top divider.
    component SliderRow: Item {
        id: sr
        property string label: ""
        property string unit: ""
        property real from: 0
        property real to: 1
        property real value: 0
        property bool first: false
        signal moved(real v)
        width: parent ? parent.width : 0
        implicitHeight: 66
        Rectangle {
            visible: !sr.first
            anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: Theme.s4; rightMargin: Theme.s4 }
            height: 1; color: Theme.hairline
        }
        StyledText {
            id: srLabel
            anchors { left: parent.left; leftMargin: Theme.s4; top: parent.top; topMargin: Theme.s3 }
            variant: "label"; text: sr.label; color: Theme.inkPrimary
        }
        StyledText {
            anchors { right: parent.right; rightMargin: Theme.s4 }
            capCentreIn: srLabel
            variant: "label"; font.features: { "tnum": 1 }
            text: Math.round(sr.value) + (sr.unit ? " " + sr.unit : "")
            color: Theme.inkDim
        }
        Slider {
            anchors { left: parent.left; right: parent.right; leftMargin: Theme.s4; rightMargin: Theme.s4; top: srLabel.bottom; topMargin: Theme.s2 }
            from: sr.from; to: sr.to; value: sr.value
            onMoved: sr.moved(value)
        }
    }

    // label left, toggle right.
    component ToggleRow: Item {
        id: tr
        property string label: ""
        property bool first: false
        property bool checked: false
        signal toggled(bool v)
        width: parent ? parent.width : 0
        implicitHeight: 48
        Rectangle {
            visible: !tr.first
            anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: Theme.s4; rightMargin: Theme.s4 }
            height: 1; color: Theme.hairline
        }
        StyledText {
            anchors { left: parent.left; leftMargin: Theme.s4 }
            capCentreIn: parent
            variant: "label"; text: tr.label; color: Theme.inkPrimary
        }
        Toggle {
            anchors { right: parent.right; rightMargin: Theme.s4; verticalCenter: parent.verticalCenter }
            checked: tr.checked
            onToggled: v => tr.toggled(v)
        }
    }

    // label left, value + chevron right, whole row is a button (hands off to a morph).
    component LinkRow: Item {
        id: lr
        property string label: ""
        property string value: ""
        property bool first: false
        signal activated()
        width: parent ? parent.width : 0
        implicitHeight: 48
        Rectangle {
            anchors.fill: parent
            color: lrMa.containsMouse ? Theme.fillLow : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
        }
        Rectangle {
            visible: !lr.first
            anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: Theme.s4; rightMargin: Theme.s4 }
            height: 1; color: Theme.hairline
        }
        StyledText {
            anchors { left: parent.left; leftMargin: Theme.s4 }
            capCentreIn: parent
            variant: "label"; text: lr.label; color: Theme.inkPrimary
        }
        Row {
            anchors { right: parent.right; rightMargin: Theme.s4; verticalCenter: parent.verticalCenter }
            spacing: Theme.s1
            StyledText { capCentreIn: parent; variant: "label"; text: lr.value; color: Theme.inkDim }
            Icon { anchors.verticalCenter: parent.verticalCenter; name: "back"; rotation: 180; size: 14; color: Theme.inkFaint }
        }
        MouseArea {
            id: lrMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: lr.activated()
        }
    }

    // label left, editable text field right (font names and the like).
    component TextRow: Item {
        id: txr
        property string label: ""
        property string value: ""
        property bool first: false
        signal committed(string t)
        width: parent ? parent.width : 0
        implicitHeight: 48
        Rectangle {
            visible: !txr.first
            anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: Theme.s4; rightMargin: Theme.s4 }
            height: 1; color: Theme.hairline
        }
        StyledText {
            anchors { left: parent.left; leftMargin: Theme.s4 }
            capCentreIn: parent
            variant: "label"; text: txr.label; color: Theme.inkPrimary
        }
        Rectangle {
            anchors { right: parent.right; rightMargin: Theme.s4; verticalCenter: parent.verticalCenter }
            width: Math.min(240, parent.width * 0.5); height: 30
            radius: Theme.rSm
            // Focused = lifted fill + accent ring; unfocused = EXACTLY the resting look it
            // had before it was ever clicked. Both properties animate back, so clicking away
            // leaves no lingering highlight.
            color: tf.activeFocus ? Theme.fillHigh : Theme.fillLow
            border.width: 1
            border.color: tf.activeFocus ? Theme.accent : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
            Behavior on border.color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
            TextInput {
                id: tf
                anchors.fill: parent
                anchors.leftMargin: Theme.s2
                anchors.rightMargin: Theme.s2
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Theme.inkPrimary
                font.family: Theme.fontBody
                font.pixelSize: Theme.fsLabel
                text: txr.value
                // commit on Enter or when focus leaves, not per keystroke (every letter
                // would otherwise be a font lookup + a config write)
                onAccepted: { txr.committed(text); win.dropFocus(); }
                onActiveFocusChanged: if (!activeFocus && text !== txr.value) txr.committed(text)
                Keys.onEscapePressed: { text = Qt.binding(() => txr.value); win.dropFocus(); }
            }
            // I-beam on hover. NoButton so the TextInput still gets every click itself
            // (caret placement, selection drags). This only paints the cursor shape.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                hoverEnabled: true
                cursorShape: Qt.IBeamCursor
            }
        }
    }

    // small caps section heading between cards
    component SectionLabel: StyledText {
        variant: "caption"
        color: Theme.inkFaint
    }

    // No Esc-to-close: this is a normal desktop window, and Esc is too easy to hit while
    // typing in a field (a font name, the search box) to have it throw the window away.
    // Close it from the shortcut / `qs ipc call settings toggle` / the WM instead.

    // Somewhere harmless to park keyboard focus. Text fields keep activeFocus (and so keep
    // their focused fill + accent ring) until something else takes it. Clicking empty space
    // wouldn't otherwise release them, leaving a field lit up long after you'd moved on.
    Item { id: focusSink }
    function dropFocus() { focusSink.forceActiveFocus(); }

    Row {
        anchors.fill: parent

        // click anywhere that isn't itself interactive → let go of the focused field
        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: win.dropFocus()
        }

        // ───────────────────────── sidebar ─────────────────────────
        Rectangle {
            id: sidebar
            width: 236
            height: parent.height
            color: Theme.surfaceBase

            Column {
                anchors.fill: parent
                anchors.margins: Theme.s3
                spacing: Theme.s3

                // search
                Item {
                    id: searchRow
                    width: parent.width
                    height: 34

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.rSm
                        // same focus treatment as the TextRow fields, and back to plain fillLow
                        // the moment focus leaves
                        color: searchField.activeFocus ? Theme.fillHigh : Theme.fillLow
                        border.width: 1
                        border.color: searchField.activeFocus ? Theme.accent : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                        Behavior on border.color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                        // I-beam over the whole field (NoButton, so clicks still reach the input)
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            hoverEnabled: true
                            cursorShape: Qt.IBeamCursor
                        }
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.s3
                            anchors.rightMargin: Theme.s3
                            spacing: Theme.s2
                            Icon { anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 14; color: Theme.inkFaint }
                            TextInput {
                                id: searchField
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 30
                                color: Theme.inkPrimary
                                font.family: Theme.fontBody
                                font.pixelSize: Theme.fsLabel
                                clip: true
                                onTextChanged: win.filter = text
                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: searchField.text === ""
                                    text: "Search Settings"
                                    color: Theme.inkFaint
                                    font: searchField.font
                                }
                            }
                        }
                    }
                }

                // category list
                Column {
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: win.cats
                        delegate: Rectangle {
                            id: catDel
                            required property var modelData
                            required property int index
                            readonly property bool selected: win.currentIndex === index
                            visible: win.filter === "" || modelData.label.toLowerCase().includes(win.filter.toLowerCase())
                            width: parent.width
                            height: 44
                            radius: Theme.rMd
                            // image.png style: monochrome, no accent. Selected = a subtle grey card,
                            // hover = a fainter grey fill, otherwise transparent.
                            color: catDel.selected ? Theme.fillHigh
                                 : catMa.containsMouse ? Theme.fillLow : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                            Row {
                                anchors { left: parent.left; leftMargin: Theme.s2; verticalCenter: parent.verticalCenter }
                                spacing: Theme.s2
                                // circular badge, monochrome. Inverts on selection: a light disc with
                                // a dark glyph, exactly like the reference's active row.
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 32; height: 32; radius: width / 2
                                    // accent woven in: a faint accent-tinted disc with an accent
                                    // glyph, flipping to a solid accent disc + ink-on-accent glyph
                                    // when active. Tracks whatever accent matugen hands the theme.
                                    color: catDel.selected ? Theme.accent : Theme.alpha(Theme.accent, 0.18)
                                    Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.glyph
                                        font.family: "Material Symbols Rounded"
                                        font.variableAxes: ({ "FILL": 1, "wght": 500, "opsz": 24 })
                                        font.pixelSize: 18
                                        color: catDel.selected ? Theme.onAccent : Theme.accent
                                    }
                                }
                                StyledText {
                                    capCentreIn: parent
                                    variant: "label"
                                    text: modelData.label
                                    color: Theme.inkPrimary
                                }
                            }
                            MouseArea {
                                id: catMa
                                anchors.fill: parent
                                hoverEnabled: true
                                // plain arrow over sidebar rows (the reference doesn't use a pointing hand)
                                onClicked: win.currentIndex = index
                            }
                        }
                    }
                }
            }
        }

        // ───────────────────────── detail ─────────────────────────
        Item {
            id: detail
            width: parent.width - sidebar.width
            height: parent.height

            readonly property int pad: Theme.s5

            // back / forward across categories
            Row {
                id: navRow
                anchors { top: parent.top; left: parent.left; topMargin: Theme.s3; leftMargin: Theme.s4 }
                height: 30
                spacing: Theme.s1
                Rectangle {
                    width: 34; height: 28; radius: Theme.rSm
                    opacity: win.currentIndex > 0 ? 1 : 0.4
                    color: (backMa.containsMouse && win.currentIndex > 0) ? Theme.fillHigh : Theme.fillLow
                    Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                    Icon { anchors.centerIn: parent; name: "back"; size: 14; color: Theme.inkPrimary }
                    MouseArea { id: backMa; anchors.fill: parent; enabled: win.currentIndex > 0; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.currentIndex-- }
                }
                Rectangle {
                    width: 34; height: 28; radius: Theme.rSm
                    opacity: win.currentIndex < win.cats.length - 1 ? 1 : 0.4
                    color: (fwdMa.containsMouse && win.currentIndex < win.cats.length - 1) ? Theme.fillHigh : Theme.fillLow
                    Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                    Icon { anchors.centerIn: parent; name: "back"; rotation: 180; size: 14; color: Theme.inkPrimary }
                    MouseArea { id: fwdMa; anchors.fill: parent; enabled: win.currentIndex < win.cats.length - 1; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.currentIndex++ }
                }
            }

            Flickable {
                id: flick
                anchors { top: navRow.bottom; topMargin: Theme.s2; left: parent.left; right: parent.right; bottom: parent.bottom }
                contentWidth: width
                contentHeight: contentCol.implicitHeight + detail.pad * 2
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // Dragging with the left button must NOT pan the page: this is a desktop
                // window, and a stray drag while reaching for a slider would fling the whole
                // view. `interactive: false` kills drag AND the built-in wheel, so the wheel
                // is handled explicitly below.
                interactive: false

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (ev) => {
                        const dy = ev.angleDelta.y !== 0 ? ev.angleDelta.y : ev.pixelDelta.y;
                        if (dy === 0) return;
                        const maxY = Math.max(0, flick.contentHeight - flick.height);
                        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY - dy));
                    }
                }

                // keep the view in range when the page (or the window) changes size, so a
                // short page can't leave you scrolled past its end
                onContentHeightChanged: contentY = Math.max(0, Math.min(contentY, Math.max(0, contentHeight - height)))
                onHeightChanged: contentY = Math.max(0, Math.min(contentY, Math.max(0, contentHeight - height)))

                Column {
                    id: contentCol
                    x: detail.pad
                    y: 0
                    width: flick.width - detail.pad * 2
                    spacing: Theme.s3

                    // ── header block (icon + title + description), changes per category ──
                    Rectangle {
                        width: parent.width
                        radius: Theme.rMd
                        color: Theme.surfacePanel
                        implicitHeight: headerCol.implicitHeight + Theme.s5 * 2
                        Column {
                            id: headerCol
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.s5 * 2
                            spacing: Theme.s2
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 62; height: 62; radius: width / 2   // circular accent-tinted disc, like the sidebar badges
                                color: Theme.alpha(Theme.accent, 0.18)
                                Text { anchors.centerIn: parent; text: win.cat.glyph; font.family: "Material Symbols Rounded"; font.variableAxes: ({ "FILL": 1, "wght": 500, "opsz": 40 }); font.pixelSize: 34; color: Theme.accent }
                            }
                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                variant: "title"
                                text: win.cat.label
                                color: Theme.inkPrimary
                            }
                            StyledText {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                variant: "label"
                                text: win.cat.desc
                                color: Theme.inkDim
                            }
                        }
                    }

                    // ── BAR & ISLAND ──
                    Column {
                        visible: win.cat.key === "bar"
                        width: parent.width
                        spacing: Theme.s3
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: barShapeCol.implicitHeight
                            Column {
                                id: barShapeCol
                                width: parent.width
                                ToggleRow { first: true; label: "Notch mode"; checked: Config.notchMode; onToggled: v => Config.notchMode = v }
                                SliderRow { visible: Config.notchMode; label: "Notch flare"; unit: "px"; from: 0; to: 24; value: Config.notchFlare; onMoved: Config.notchFlare = Math.round(v) }
                                SliderRow { label: "Bar height"; unit: "px"; from: 24; to: 64; value: Config.barHeight; onMoved: Config.barHeight = Math.round(v) }
                                SliderRow { label: "Collapsed width"; unit: "px"; from: 90; to: 400; value: Config.islandCollapsedWidth; onMoved: Config.islandCollapsedWidth = Math.round(v) }
                                SliderRow { label: "Expanded height"; unit: "px"; from: 80; to: 200; value: Config.islandExpandedHeight; onMoved: Config.islandExpandedHeight = Math.round(v) }
                                SliderRow { label: "Gap from screen edge"; unit: "px"; from: 0; to: 32; value: Config.islandGap; onMoved: Config.islandGap = Math.round(v) }
                                SliderRow { label: "Inner padding"; unit: "px"; from: 0; to: 16; value: Config.islandPadding; onMoved: Config.islandPadding = Math.round(v) }
                                SliderRow { label: "Corner radius"; unit: "px"; from: 0; to: 40; value: Config.islandRadius; onMoved: Config.islandRadius = Math.round(v) }
                                SliderRow { label: "Corner radius (expanded)"; unit: "px"; from: 0; to: 48; value: Config.islandRadiusOpen; onMoved: Config.islandRadiusOpen = Math.round(v) }
                                SliderRow { label: "Minimum expanded width"; unit: "px"; from: 360; to: 1200; value: Config.islandMinWidth; onMoved: Config.islandMinWidth = Math.round(v) }
                            }
                        }
                        SectionLabel { text: "Game mode" }
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: gameCol.implicitHeight
                            Column {
                                id: gameCol
                                width: parent.width
                                SliderRow { first: true; label: "Bar height"; unit: "px"; from: 28; to: 72; value: Config.gameBarHeight; onMoved: Config.gameBarHeight = Math.round(v) }
                                SliderRow { label: "Cluster gap"; unit: "px"; from: 40; to: 400; value: Config.gameClusterGap; onMoved: Config.gameClusterGap = Math.round(v) }
                            }
                        }
                        SectionLabel { text: "Panel widths" }
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: panelCol.implicitHeight
                            Column {
                                id: panelCol
                                width: parent.width
                                SliderRow { first: true; label: "Launcher"; unit: "px"; from: 380; to: 1000; value: Config.launcherWidth; onMoved: Config.launcherWidth = Math.round(v) }
                                SliderRow { label: "Control center"; unit: "px"; from: 460; to: 760; value: Config.controlCenterWidth; onMoved: Config.controlCenterWidth = Math.round(v) }
                                SliderRow { label: "Calendar"; unit: "px"; from: 260; to: 560; value: Config.calendarWidth; onMoved: Config.calendarWidth = Math.round(v) }
                                SliderRow { label: "Wallpaper picker"; unit: "px"; from: 600; to: 1600; value: Config.wallpaperPickerWidth; onMoved: Config.wallpaperPickerWidth = Math.round(v) }
                                SliderRow { label: "Notification"; unit: "px"; from: 320; to: 800; value: Config.notificationWidth; onMoved: Config.notificationWidth = Math.round(v) }
                                SliderRow { label: "Volume / brightness OSD"; unit: "px"; from: 200; to: 520; value: Config.osdWidth; onMoved: Config.osdWidth = Math.round(v) }
                            }
                        }
                        SectionLabel { text: "Window manager" }
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: wmCol.implicitHeight
                            Column {
                                id: wmCol
                                width: parent.width
                                SliderRow { first: true; label: "Hyprland gaps_out"; unit: "px"; from: 0; to: 40; value: Config.hyprGapsOut; onMoved: Config.hyprGapsOut = Math.round(v) }
                            }
                        }
                    }

                    // ── MEDIA ──
                    Column {
                        visible: win.cat.key === "media"
                        width: parent.width
                        spacing: Theme.s3
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: mediaCol.implicitHeight
                            Column {
                                id: mediaCol
                                width: parent.width
                                SliderRow { first: true; label: "Song name width"; unit: "px"; from: 60; to: 300; value: Config.mediaTitleWidth; onMoved: Config.mediaTitleWidth = Math.round(v) }
                                SliderRow { label: "Album art size"; unit: "px"; from: 40; to: 140; value: Config.mediaArtSize; onMoved: Config.mediaArtSize = Math.round(v) }
                            }
                        }
                        SectionLabel { text: "What to show" }
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: mediaShowCol.implicitHeight
                            Column {
                                id: mediaShowCol
                                width: parent.width
                                ToggleRow { first: true; label: "Album line"; checked: Config.mediaShowAlbum; onToggled: v => Config.mediaShowAlbum = v }
                                ToggleRow { label: "Artist line"; checked: Config.mediaShowArtist; onToggled: v => Config.mediaShowArtist = v }
                                ToggleRow { label: "Transport buttons"; checked: Config.mediaShowTransport; onToggled: v => Config.mediaShowTransport = v }
                                ToggleRow { label: "Scroll to change track"; checked: Config.mediaScrollSwitch; onToggled: v => Config.mediaScrollSwitch = v }
                            }
                        }
                    }

                    // ── CLOCK & DATE ──
                    Column {
                        visible: win.cat.key === "clock"
                        width: parent.width
                        spacing: Theme.s3
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: clockCol.implicitHeight
                            Column {
                                id: clockCol
                                width: parent.width
                                ToggleRow { first: true; label: "24-hour time"; checked: Config.clock24h; onToggled: v => Config.clock24h = v }
                                ToggleRow { label: "Show seconds"; checked: Config.clockSeconds; onToggled: v => Config.clockSeconds = v }
                                ToggleRow { label: "Workspace dots beside the clock"; checked: Config.clockDots; onToggled: v => Config.clockDots = v }
                                ToggleRow { label: "Battery and Wi-Fi beside the clock"; checked: Config.clockStatus; onToggled: v => Config.clockStatus = v }
                            }
                        }
                        SectionLabel { text: "Expanded island" }
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: openCol.implicitHeight
                            Column {
                                id: openCol
                                width: parent.width
                                ToggleRow { first: true; label: "Workspaces on the left"; checked: Config.islandWorkspaces; onToggled: v => Config.islandWorkspaces = v }
                                ToggleRow { label: "Status on the right"; checked: Config.islandStatus; onToggled: v => Config.islandStatus = v }
                                ToggleRow { label: "Media card under the clock"; checked: Config.islandMedia; onToggled: v => Config.islandMedia = v }
                            }
                        }
                        SectionLabel { text: "Calendar" }
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: calCol.implicitHeight
                            Column {
                                id: calCol
                                width: parent.width
                                SliderRow { first: true; label: "Week starts on"; from: 0; to: 6; value: Config.weekStartsOn; onMoved: Config.weekStartsOn = Math.round(v) }
                                SliderRow { label: "Day cell height"; unit: "px"; from: 22; to: 48; value: Config.calendarCellHeight; onMoved: Config.calendarCellHeight = Math.round(v) }
                                ToggleRow { label: "Show neighbouring months"; checked: Config.calendarShowAdjacent; onToggled: v => Config.calendarShowAdjacent = v }
                            }
                        }
                    }

                    // ── APPEARANCE ──
                    Column {
                        visible: win.cat.key === "appearance"
                        width: parent.width
                        spacing: Theme.s3
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: appCol.implicitHeight
                            Column {
                                id: appCol
                                width: parent.width
                                LinkRow { first: true; label: "Wallpaper"; value: "Choose…"; onActivated: { GlobalState.settingsOpen = false; GlobalState.wallpaperPickerOpen = true; } }
                            }
                        }
                        SectionLabel { text: "Glass" }
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: glassCol.implicitHeight
                            Column {
                                id: glassCol
                                width: parent.width
                                ToggleRow { first: true; label: "Blur behind panels"; checked: Config.blur; onToggled: v => Config.blur = v }
                                SliderRow { label: "Pane opacity"; unit: "%"; from: 30; to: 100; value: Config.glassOpacity; onMoved: Config.glassOpacity = Math.round(v) }
                                SliderRow { label: "Stacked pane opacity"; unit: "%"; from: 30; to: 100; value: Config.glassStrongOpacity; onMoved: Config.glassStrongOpacity = Math.round(v) }
                                SliderRow { label: "Rim"; unit: "%"; from: 0; to: 40; value: Config.rimAlpha; onMoved: Config.rimAlpha = Math.round(v) }
                                SliderRow { label: "Selected row"; unit: "%"; from: 0; to: 30; value: Config.selectionAlpha; onMoved: Config.selectionAlpha = Math.round(v) }
                            }
                        }
                        SectionLabel { text: "Accent" }
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: accentCol.implicitHeight
                            Column {
                                id: accentCol
                                width: parent.width
                                // swatches: the scheme's own accent first, then its palette; the
                                // current pick wears a ring
                                Item {
                                    width: parent.width; implicitHeight: 48
                                    StyledText { anchors { left: parent.left; leftMargin: Theme.s4 } capCentreIn: parent; variant: "label"; text: "Accent colour"; color: Theme.inkPrimary }
                                    Row {
                                        anchors { right: parent.right; rightMargin: Theme.s4; verticalCenter: parent.verticalCenter }
                                        spacing: Theme.s2
                                        Repeater {
                                            model: [ { c: "", label: "scheme" }, { c: Theme.hues[0] }, { c: Theme.hues[1] }, { c: Theme.hues[2] }, { c: Theme.hues[3] }, { c: Theme.hues[4] }, { c: Theme.hues[5] } ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                readonly property string hex: modelData.c === "" ? "" : String(modelData.c)
                                                readonly property bool picked: (Config.accentOverride.toLowerCase() === hex.toLowerCase())
                                                width: 22; height: 22; radius: 11
                                                color: hex === "" ? Theme.schemeAccent : modelData.c
                                                border.width: picked ? 2 : 0
                                                border.color: Theme.inkPrimary
                                                Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: Theme.base; visible: parent.hex === "" }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Config.accentOverride = parent.hex }
                                            }
                                        }
                                    }
                                }
                                TextRow { label: "Custom (#rrggbb)"; value: Config.accentOverride; onCommitted: t => { const v = t.trim(); if (v === "" || /^#[0-9a-fA-F]{6}$/.test(v)) Config.accentOverride = v; } }
                                ToggleRow { label: "Color burst (a different palette colour per surface)"; checked: Config.colorBurst; onToggled: v => Config.colorBurst = v }
                            }
                        }
                        SectionLabel { text: "Type" }
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: typeCol.implicitHeight
                            Column {
                                id: typeCol
                                width: parent.width
                                SliderRow { first: true; label: "Font size"; unit: "px"; from: 10; to: 22; value: Config.fontSize; onMoved: Config.fontSize = Math.round(v) }
                                TextRow { label: "Body font"; value: Config.fontBody; onCommitted: t => Config.fontBody = t }
                                TextRow { label: "Display font"; value: Config.fontDisplay; onCommitted: t => Config.fontDisplay = t }
                            }
                        }
                        SectionLabel { text: "Shape & depth" }
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: shapeCol.implicitHeight
                            Column {
                                id: shapeCol
                                width: parent.width
                                SliderRow { first: true; label: "Spacing unit"; unit: "px"; from: 2; to: 6; value: Config.spacingUnit; onMoved: Config.spacingUnit = Math.round(v) }
                                SliderRow { label: "Small radius"; unit: "px"; from: 0; to: 24; value: Config.radiusSmall; onMoved: Config.radiusSmall = Math.round(v) }
                                SliderRow { label: "Medium radius"; unit: "px"; from: 0; to: 28; value: Config.radiusMedium; onMoved: Config.radiusMedium = Math.round(v) }
                                SliderRow { label: "Large radius"; unit: "px"; from: 0; to: 32; value: Config.radiusLarge; onMoved: Config.radiusLarge = Math.round(v) }
                                ToggleRow { label: "Screen corners"; checked: Config.screenCorners; onToggled: v => Config.screenCorners = v }
                                SliderRow { label: "Screen corner radius"; unit: "px"; from: 0; to: 40; value: Config.screenCornerRadius; onMoved: Config.screenCornerRadius = Math.round(v) }
                                SliderRow { label: "Icon size"; unit: "px"; from: 12; to: 28; value: Config.iconSize; onMoved: Config.iconSize = Math.round(v) }
                                SliderRow { label: "Icon stroke"; unit: "×10"; from: 10; to: 34; value: Config.iconStroke; onMoved: Config.iconStroke = Math.round(v) }
                            }
                        }
                        SectionLabel { text: "Surfaces & ink" }
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: surfCol.implicitHeight
                            Column {
                                id: surfCol
                                width: parent.width
                                SliderRow { first: true; label: "Surface lift"; unit: "%"; from: 0; to: 20; value: Config.surfaceTint; onMoved: Config.surfaceTint = Math.round(v) }
                                SliderRow { label: "Divider strength"; unit: "%"; from: 0; to: 40; value: Config.hairlineAlpha; onMoved: Config.hairlineAlpha = Math.round(v) }
                                SliderRow { label: "Secondary text"; unit: "%"; from: 30; to: 90; value: Config.inkDimAlpha; onMoved: Config.inkDimAlpha = Math.round(v) }
                                SliderRow { label: "Tertiary text"; unit: "%"; from: 10; to: 70; value: Config.inkFaintAlpha; onMoved: Config.inkFaintAlpha = Math.round(v) }
                                SliderRow { label: "Hover fill"; unit: "%"; from: 0; to: 20; value: Config.fillLowAlpha; onMoved: Config.fillLowAlpha = Math.round(v) }
                                SliderRow { label: "Selected fill"; unit: "%"; from: 0; to: 35; value: Config.fillHighAlpha; onMoved: Config.fillHighAlpha = Math.round(v) }
                                SliderRow { label: "Modal dim"; unit: "%"; from: 0; to: 90; value: Config.scrimOpacity; onMoved: Config.scrimOpacity = Math.round(v) }
                            }
                        }
                        SectionLabel { text: "Shadow" }
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: shadCol.implicitHeight
                            Column {
                                id: shadCol
                                width: parent.width
                                SliderRow { first: true; label: "Opacity"; unit: "%"; from: 0; to: 100; value: Config.shadowOpacity; onMoved: Config.shadowOpacity = Math.round(v) }
                                SliderRow { label: "Blur"; unit: "%"; from: 0; to: 100; value: Config.shadowBlur; onMoved: Config.shadowBlur = Math.round(v) }
                                SliderRow { label: "Vertical offset"; unit: "px"; from: 0; to: 32; value: Config.shadowOffsetY; onMoved: Config.shadowOffsetY = Math.round(v) }
                                SliderRow { label: "Spread"; unit: "px"; from: 0; to: 160; value: Config.shadowSpread; onMoved: Config.shadowSpread = Math.round(v) }
                            }
                        }
                        SectionLabel { text: "Wallpaper" }
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: wpCol.implicitHeight
                            Column {
                                id: wpCol
                                width: parent.width
                                SliderRow { first: true; label: "Crossfade"; unit: "ms"; from: 0; to: 2000; value: Config.wallpaperFade; onMoved: Config.wallpaperFade = Math.round(v) }
                            }
                        }
                    }

                    // ── MOTION ──
                    Column {
                        visible: win.cat.key === "motion"
                        width: parent.width
                        spacing: Theme.s3
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: motionCol.implicitHeight
                            Column {
                                id: motionCol
                                width: parent.width
                                ToggleRow { first: true; label: "Reduce motion"; checked: Config.reducedMotion; onToggled: v => Config.reducedMotion = v }
                                SliderRow { visible: !Config.reducedMotion; label: "Movement (size / position)"; unit: "ms"; from: 80; to: 800; value: Config.motionSpring; onMoved: Config.motionSpring = Math.round(v) }
                                SliderRow { visible: !Config.reducedMotion; label: "Fades & colour"; unit: "ms"; from: 40; to: 600; value: Config.motionEffects; onMoved: Config.motionEffects = Math.round(v) }
                                SliderRow { visible: !Config.reducedMotion; label: "Hover response"; unit: "ms"; from: 0; to: 400; value: Config.motionFast; onMoved: Config.motionFast = Math.round(v) }
                                SliderRow { visible: !Config.reducedMotion; label: "Bounce"; unit: "%"; from: 0; to: 100; value: Config.motionBounce; onMoved: Config.motionBounce = Math.round(v) }
                            }
                        }
                    }

                    // ── LAUNCHER ──
                    Column {
                        visible: win.cat.key === "launcher"
                        width: parent.width
                        spacing: Theme.s3
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: lchCol.implicitHeight
                            Column {
                                id: lchCol
                                width: parent.width
                                SliderRow { first: true; label: "Width"; unit: "px"; from: 380; to: 1000; value: Config.launcherWidth; onMoved: Config.launcherWidth = Math.round(v) }
                                SliderRow { label: "Row height"; unit: "px"; from: 32; to: 72; value: Config.launcherRowHeight; onMoved: Config.launcherRowHeight = Math.round(v) }
                                SliderRow { label: "Rows before scrolling"; from: 3; to: 15; value: Config.launcherMaxRows; onMoved: Config.launcherMaxRows = Math.round(v) }
                            }
                        }
                    }

                    // ── NOTIFICATIONS ──
                    Column {
                        visible: win.cat.key === "notif"
                        width: parent.width
                        spacing: Theme.s3
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: notifCol.implicitHeight
                            Column {
                                id: notifCol
                                width: parent.width
                                SliderRow { first: true; label: "Popup timeout"; unit: "ms"; from: 500; to: 15000; value: Config.notifTimeout; onMoved: Config.notifTimeout = Math.round(v) }
                                SliderRow { label: "Urgent timeout"; unit: "ms"; from: 1000; to: 60000; value: Config.notifTimeoutCritical; onMoved: Config.notifTimeoutCritical = Math.round(v) }
                                SliderRow { label: "Width"; unit: "px"; from: 320; to: 800; value: Config.notificationWidth; onMoved: Config.notificationWidth = Math.round(v) }
                                ToggleRow { label: "Show body text"; checked: Config.notifShowBody; onToggled: v => Config.notifShowBody = v }
                                SliderRow { label: "History height"; unit: "px"; from: 100; to: 600; value: Config.notifHistoryHeight; onMoved: Config.notifHistoryHeight = Math.round(v) }
                            }
                        }
                        SectionLabel { text: "VOLUME / BRIGHTNESS OSD" }
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: osdCol.implicitHeight
                            Column {
                                id: osdCol
                                width: parent.width
                                SliderRow { first: true; label: "On-screen time"; unit: "ms"; from: 400; to: 6000; value: Config.osdTimeout; onMoved: Config.osdTimeout = Math.round(v) }
                                SliderRow { label: "Level bar thickness"; unit: "px"; from: 4; to: 16; value: Config.osdBarHeight; onMoved: Config.osdBarHeight = Math.round(v) }
                            }
                        }
                        SectionLabel { text: "Toast" }
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: hudCol.implicitHeight
                            Column {
                                id: hudCol
                                width: parent.width
                                SliderRow { first: true; label: "On-screen time"; unit: "ms"; from: 600; to: 5000; value: Config.hudTimeout; onMoved: Config.hudTimeout = Math.round(v) }
                            }
                        }
                    }

                    // ── LOCK SCREEN ──
                    Column {
                        visible: win.cat.key === "lock"
                        width: parent.width
                        spacing: Theme.s3
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: lockCol.implicitHeight
                            Column {
                                id: lockCol
                                width: parent.width
                                SliderRow { first: true; label: "Blur"; unit: "px"; from: 0; to: 128; value: Config.lockBlur; onMoved: Config.lockBlur = Math.round(v) }
                                SliderRow { label: "Dim"; unit: "%"; from: 0; to: 60; value: Config.lockDim; onMoved: Config.lockDim = Math.round(v) }
                                SliderRow { label: "Snapshot quality"; unit: "%"; from: 40; to: 100; value: Config.lockShotQuality; onMoved: Config.lockShotQuality = Math.round(v) }
                                ToggleRow { label: "Show password dots"; checked: Config.lockShowDots; onToggled: v => Config.lockShowDots = v }
                                SliderRow { label: "Caret blink"; unit: "ms"; from: 200; to: 1200; value: Config.caretBlink; onMoved: Config.caretBlink = Math.round(v) }
                            }
                        }
                    }

                    // ── SYSTEM ──
                    Column {
                        visible: win.cat.key === "system"
                        width: parent.width
                        spacing: Theme.s3
                        Rectangle {
                            width: parent.width; radius: Theme.rMd; color: Theme.surfacePanel
                            implicitHeight: sysCol.implicitHeight
                            Column {
                                id: sysCol
                                width: parent.width
                                SliderRow { first: true; label: "Brightness step"; unit: "%"; from: 1; to: 25; value: Config.brightnessStep; onMoved: Config.brightnessStep = Math.round(v) }
                                SliderRow { label: "Volume step"; unit: "%"; from: 1; to: 25; value: Config.volumeStep; onMoved: Config.volumeStep = Math.round(v) }
                                SliderRow { label: "Backlight poll"; unit: "ms"; from: 500; to: 10000; value: Config.brightnessPoll; onMoved: Config.brightnessPoll = Math.round(v) }
                                SliderRow { label: "Low battery at"; unit: "%"; from: 5; to: 50; value: Config.batteryLowThreshold; onMoved: Config.batteryLowThreshold = Math.round(v) }
                                SliderRow { label: "Night Light warmth"; unit: "K"; from: 1500; to: 6500; value: Config.nightLightTemp; onMoved: Config.nightLightTemp = Math.round(v) }
                            }
                        }
                    }

                    // ── CONTROL CENTER ──
                    // The mosaic is a free-placement grid the user arranges by hand, so this
                    // page IS the editor: the real controls at their real size, dragged,
                    // resized and swapped in place (CcLayoutEditor, writing Config.ccLayout).
                    Column {
                        visible: win.cat.key === "cc"
                        width: parent.width
                        spacing: Theme.s3

                        SectionLabel { text: "Layout" }
                        CcLayoutEditor { width: parent.width }
                        StyledText {
                            width: parent.width
                            wrapMode: Text.Wrap
                            variant: "caption"
                            color: Theme.inkDim
                            text: "Drag a control to move it, pull its corner to resize, right-click for every size it supports. With one selected: arrows nudge, [ and ] step through sizes, Delete removes."
                        }
                    }
                }
            }

            // ── scrollbar ──
            // Hand-rolled to match the shell (no QtQuick.Controls anywhere else here) and
            // because the Flickable is interactive:false, so nothing else would draw one.
            // Thumb height tracks the visible fraction; dragging it (or clicking the track)
            // drives contentY directly.
            Item {
                id: sbar
                anchors { right: flick.right; rightMargin: 3; top: flick.top; topMargin: 4; bottom: flick.bottom; bottomMargin: 4 }
                width: 12
                visible: flick.contentHeight > flick.height + 1
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects) } }

                readonly property real maxY: Math.max(0, flick.contentHeight - flick.height)
                readonly property real thumbH: Math.max(36, height * Math.min(1, flick.height / Math.max(1, flick.contentHeight)))
                readonly property real travel: Math.max(0, height - thumbH)

                function scrollTo(topY) {
                    if (travel <= 0) return;
                    const r = Math.max(0, Math.min(1, topY / travel));
                    flick.contentY = r * maxY;
                }

                Rectangle {
                    id: sbThumb
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: (sbMa.containsMouse || sbMa.pressed) ? 8 : 5
                    height: sbar.thumbH
                    radius: width / 2
                    y: sbar.maxY <= 0 ? 0 : (flick.contentY / sbar.maxY) * sbar.travel
                    color: sbMa.pressed ? Theme.inkDim
                         : sbMa.containsMouse ? Theme.alpha(Theme.foreground, 0.3)
                         : Theme.fillHigh
                    Behavior on width { NumberAnimation { duration: Theme.dur(Theme.dFast); easing.type: Theme.easeOut } }
                    Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                }

                MouseArea {
                    id: sbMa
                    anchors.fill: parent
                    hoverEnabled: true
                    property real grabDy: 0
                    onPressed: (m) => {
                        // grabbed the thumb → keep the offset; clicked the track → jump, centred
                        if (m.y >= sbThumb.y && m.y <= sbThumb.y + sbThumb.height) {
                            grabDy = m.y - sbThumb.y;
                        } else {
                            grabDy = sbThumb.height / 2;
                            sbar.scrollTo(m.y - grabDy);
                        }
                    }
                    onPositionChanged: (m) => { if (pressed) sbar.scrollTo(m.y - grabDy); }
                }
            }

        }
    }
}
