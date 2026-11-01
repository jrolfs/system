pragma Singleton
import Quickshell
import Quickshell.Io
import "CcLayout.js" as CcLayout

// User settings, read from and written back to $XDG_STATE_HOME/quickshell/settings.json.
// Home-manager rewrites that file from the Nix declaration on every switch, so what Nix
// declares wins, while the Settings window can still try values out live in between.
// Anything the declaration leaves out falls back to the defaults below.
Singleton {
    id: root

    // ── bar / island shape ──
    property alias barHeight: adapter.barHeight
    // ── glass (see Theme.qml) ──
    property alias blur: adapter.blur                         // ask the compositor to blur behind surfaces
    property alias glassOpacity: adapter.glassOpacity         // %, the pane over the blur
    property alias glassStrongOpacity: adapter.glassStrongOpacity // %, a pane stacked on glass
    property alias rimAlpha: adapter.rimAlpha                 // %, the light edge around a pane
    property alias selectionAlpha: adapter.selectionAlpha     // %, the highlighted row
    // ── Hyprland's own values, so Game Mode can put them back ──
    property alias hyprGapsIn: adapter.hyprGapsIn
    property alias hyprRounding: adapter.hyprRounding
    // ── wallpapers the picker offers ──
    property alias wallpaperDir: adapter.wallpaperDir
    property alias notchMode: adapter.notchMode               // bar shape: false = floating island, true = flush top notch
    property alias notchFlare: adapter.notchFlare             // px the notch's top corners flare out (concave teardrop); 0 = square
    property alias islandCollapsedWidth: adapter.islandCollapsedWidth // px, the resting pill
    property alias islandExpandedHeight: adapter.islandExpandedHeight // px, hover/pinned height
    property alias islandMinWidth: adapter.islandMinWidth     // px floor; it grows past this to fit the media + date
    property alias islandGap: adapter.islandGap               // px above the floating island (and below, via exclusiveZone)
    property alias islandPadding: adapter.islandPadding       // px of extra inset inside the expanded island
    property alias islandRadius: adapter.islandRadius         // px corner radius, collapsed
    property alias islandRadiusOpen: adapter.islandRadiusOpen // px corner radius, expanded
    property alias hyprGapsOut: adapter.hyprGapsOut           // must match Hyprland general:gaps_out (top)
    property alias gameBarHeight: adapter.gameBarHeight       // px, Game Mode's full-width bar
    property alias gameClusterGap: adapter.gameClusterGap     // px between each card and the clock in bar form

    // ── media (the island's now-playing card) ──
    property alias mediaTitleWidth: adapter.mediaTitleWidth   // px of song name shown before it elides
    property alias mediaArtSize: adapter.mediaArtSize         // px, album art square
    property alias mediaShowAlbum: adapter.mediaShowAlbum     // show the album line
    property alias mediaShowArtist: adapter.mediaShowArtist   // show the artist line
    property alias mediaShowTransport: adapter.mediaShowTransport // show prev / play / next
    property alias mediaScrollSwitch: adapter.mediaScrollSwitch   // scroll over the art to change track

    // ── clock ──
    property alias clockSeconds: adapter.clockSeconds         // show seconds in the collapsed clock
    property alias clock24h: adapter.clock24h                 // 24-hour vs 12-hour time
    property alias clockDots: adapter.clockDots               // workspace dots beside the collapsed clock
    property alias clockStatus: adapter.clockStatus           // battery + Wi-Fi capsules beside the collapsed clock

    // ── expanded island (the pill's companions, a size up, either side of the clock) ──
    property alias islandWorkspaces: adapter.islandWorkspaces // the workspace capsules on the left
    property alias islandStatus: adapter.islandStatus         // battery + signal on the right
    property alias islandMedia: adapter.islandMedia           // the media card under the clock

    // ── panel sizes ──
    property alias launcherWidth: adapter.launcherWidth
    property alias launcherRowHeight: adapter.launcherRowHeight
    property alias launcherMaxRows: adapter.launcherMaxRows   // rows visible before it scrolls
    property alias controlCenterWidth: adapter.controlCenterWidth
    property alias calendarWidth: adapter.calendarWidth
    property alias wallpaperPickerWidth: adapter.wallpaperPickerWidth
    property alias notificationWidth: adapter.notificationWidth
    property alias osdWidth: adapter.osdWidth

    // ── notifications ──
    property alias notifTimeout: adapter.notifTimeout                 // ms a normal popup stays up
    property alias notifTimeoutCritical: adapter.notifTimeoutCritical // ms for urgency=critical
    property alias notifShowBody: adapter.notifShowBody               // show the body text, not just the summary
    property alias notifHistoryHeight: adapter.notifHistoryHeight     // px, history list cap in control center

    // ── osd (volume / brightness pill) ──
    property alias osdTimeout: adapter.osdTimeout             // ms on screen before it hides
    property alias hudTimeout: adapter.hudTimeout             // ms the "Copied to clipboard" toast holds
    property alias osdBarHeight: adapter.osdBarHeight         // px, level bar thickness
    property alias volumeStep: adapter.volumeStep             // % per key press

    // ── calendar ──
    property alias weekStartsOn: adapter.weekStartsOn         // 0 = Sunday … 6 = Saturday
    property alias calendarCellHeight: adapter.calendarCellHeight
    property alias calendarShowAdjacent: adapter.calendarShowAdjacent // dim the neighbouring months' days

    // ── lock screen ──
    property alias lockBlur: adapter.lockBlur                 // px blur radius over the freeze-frame
    property alias lockDim: adapter.lockDim                   // % scrim over the blur
    property alias lockShotQuality: adapter.lockShotQuality   // grim JPEG quality for the freeze-frame
    property alias lockShowDots: adapter.lockShowDots         // bullets in the password field
    property alias caretBlink: adapter.caretBlink             // ms, password caret blink

    // ── motion ──
    property alias reducedMotion: adapter.reducedMotion       // collapse every duration to 0
    property alias motionSpring: adapter.motionSpring         // ms, position/size moves
    property alias motionEffects: adapter.motionEffects       // ms, fades/colour
    property alias motionFast: adapter.motionFast             // ms, hover micro-interactions
    property alias motionBounce: adapter.motionBounce         // 0-100, spring overshoot on size/position moves

    // ── appearance ──
    property alias fontSize: adapter.fontSize
    property alias wallpaper: adapter.wallpaper
    property alias fontBody: adapter.fontBody                 // UI face
    property alias fontDisplay: adapter.fontDisplay           // numerals / clock face
    property alias radiusSmall: adapter.radiusSmall           // inner controls
    property alias radiusMedium: adapter.radiusMedium         // cards
    property alias radiusLarge: adapter.radiusLarge           // panels
    property alias screenCorners: adapter.screenCorners       // paint rounded corners over the display corners
    property alias screenCornerRadius: adapter.screenCornerRadius // px radius of those corners
    property alias accentOverride: adapter.accentOverride     // "" = the scheme's accent, else a #rrggbb
    property alias colorBurst: adapter.colorBurst             // every surface its own palette colour
    property alias surfaceTint: adapter.surfaceTint           // how far the near-black surfaces lift off pure black (%)
    property alias spacingUnit: adapter.spacingUnit           // px base unit; the whole s1..s6 scale derives from it
    property alias iconSize: adapter.iconSize                 // px, global icon size
    property alias iconStroke: adapter.iconStroke             // stroke weight for the drawn icon set (x10)
    property alias hairlineAlpha: adapter.hairlineAlpha       // % borders / dividers
    property alias inkDimAlpha: adapter.inkDimAlpha           // % secondary text
    property alias inkFaintAlpha: adapter.inkFaintAlpha       // % tertiary text
    property alias fillLowAlpha: adapter.fillLowAlpha         // % idle/hover fill
    property alias fillHighAlpha: adapter.fillHighAlpha       // % pressed/selected fill
    property alias scrimOpacity: adapter.scrimOpacity         // % modal backdrop dim
    property alias shadowOpacity: adapter.shadowOpacity       // floating-surface drop shadow (%)
    property alias shadowBlur: adapter.shadowBlur             // %
    property alias shadowOffsetY: adapter.shadowOffsetY       // px
    property alias shadowSpread: adapter.shadowSpread         // px, MultiEffect blurMax

    // ── system ──
    property alias brightnessStep: adapter.brightnessStep     // % per key press
    property alias brightnessPoll: adapter.brightnessPoll     // ms between internal-backlight reads
    property alias batteryLowThreshold: adapter.batteryLowThreshold // % at which battery reads "low"
    property alias nightLightTemp: adapter.nightLightTemp     // Kelvin
    property alias wallpaperFade: adapter.wallpaperFade       // ms crossfade when the wallpaper changes

    // ── control center layout ──
    // A FREE-PLACEMENT grid (iOS 18 / macOS Tahoe style: gaps allowed, they persist) of
    // square cells, edited by drag and drop in Settings. Persisted as ONE JSON string,
    // {"v":2,"columns":7,"items":[{"key","x","y","w","h"}]}. The CODE owns which controls
    // exist and which sizes each supports (ccRegistry below); the file only carries the
    // user's arrangement, so a control added here later just shows up in the gallery.
    // All geometry and collision logic is in CcLayout.js: pure functions, exercised from
    // node, because a drag-and-drop editor is the one thing that can't be verified by
    // dragging things around from a script.
    property alias ccLayout: adapter.ccLayout

    // sizes are [w,h] in cells; w = 0 means "full width" and resolves to the column count.
    // `def` is the size a control gets when added (and in the default mosaic).
    readonly property var ccRegistry: [
        { key: "wifi",          label: "Wi-Fi",         kind: "toggle",        icon: "",           sizes: [[1,1],[2,1],[3,1],[4,1],[2,2],[3,2]],                    def: [4,1] },
        { key: "bluetooth",     label: "Bluetooth",     kind: "toggle",        icon: "bluetooth",  sizes: [[1,1],[2,1],[3,1],[4,1],[2,2],[3,2]],                    def: [4,1] },
        { key: "focus",         label: "Focus",         kind: "toggle",        icon: "dnd",        sizes: [[1,1],[2,1],[3,1],[4,1],[2,2],[3,2]],                    def: [4,1] },
        { key: "nightlight",    label: "Night Light",   kind: "toggle",        icon: "night",      sizes: [[1,1],[2,1],[3,1],[4,1],[2,2]],                          def: [1,1] },
        { key: "gamemode",      label: "Game Mode",     kind: "toggle",        icon: "controller", sizes: [[1,1],[2,1],[3,1],[4,1],[2,2]],                          def: [1,1] },
        { key: "lock",          label: "Lock",          kind: "action",        icon: "lock",       sizes: [[1,1],[2,1],[3,1]],                                      def: [1,1] },
        { key: "display",       label: "Display",       kind: "slider",        icon: "brightness", sizes: [[3,1],[4,1],[5,1],[6,1],[0,1],[1,2],[2,2],[0,2]],        def: [0,1] },
        { key: "sound",         label: "Sound",         kind: "slider",        icon: "volume",     sizes: [[3,1],[4,1],[5,1],[6,1],[0,1],[1,2],[2,2],[0,2]],        def: [0,1] },
        { key: "media",         label: "Now Playing",   kind: "media",         icon: "music",      sizes: [[1,1],[2,1],[4,1],[0,1],[2,2],[3,2],[4,2],[0,2]],        def: [3,2] },
        { key: "notifications", label: "Notifications", kind: "notifications", icon: "bell",       sizes: [[0,1],[0,2],[0,3],[0,4]],                                def: [0,2] }
    ]
    function ccReg(key) {
        for (let i = 0; i < ccRegistry.length; i++) if (ccRegistry[i].key === key) return ccRegistry[i];
        return null;
    }

    // Inset of every panel the island morphs into, from the island's edge to its content.
    // Here rather than in Theme so the control center's grid maths below can use it.
    readonly property int panelPad: spacingUnit * 5

    // geometry. The control center's width minus the panel insets; the gap is the shell's
    // s3. Both are derived from Config (not Theme) so the layout math has no import cycle. The row budget is a PIXEL cap (the panel has to
    // stay on screen), so narrower grids (bigger cells) hold fewer rows.
    readonly property int ccGap: spacingUnit * 3
    readonly property int ccContentW: controlCenterWidth - panelPad * 2
    readonly property int ccMaxPx: 620
    readonly property int ccMinColumns: 5
    readonly property int ccMaxColumns: 9

    readonly property var _ccParsed: {
        try { const o = JSON.parse(ccLayout || ""); return (o && typeof o === "object") ? o : null; }
        catch (e) { return null; }
    }
    readonly property int ccColumns: Math.max(ccMinColumns, Math.min(ccMaxColumns, (_ccParsed && _ccParsed.columns) ? (_ccParsed.columns | 0) : 7))
    readonly property real ccCell: CcLayout.cellSize(ccContentW, ccColumns, ccGap)
    readonly property int ccMaxRows: CcLayout.maxRowsFor(ccContentW, ccColumns, ccGap, ccMaxPx)
    // the validated arrangement: unknown keys dropped, sizes snapped, overlaps repaired
    readonly property var ccItems: (_ccParsed && Array.isArray(_ccParsed.items))
        ? CcLayout.normalize(_ccParsed.items, ccRegistry, ccColumns, ccMaxRows)
        : CcLayout.defaults(ccRegistry, ccColumns, ccMaxRows)
    readonly property int ccRows: Math.max(1, CcLayout.rows(ccItems))
    // registry entries not currently placed (the gallery)
    readonly property var ccAvailable: ccRegistry.filter(r => !ccItems.some(i => i.key === r.key))

    function ccItem(key) {
        for (let i = 0; i < ccItems.length; i++) if (ccItems[i].key === key) return ccItems[i];
        return null;
    }
    function ccSizesFor(key) { const r = ccReg(key); return r ? CcLayout.sizesFor(r, ccColumns) : []; }
    function ccSnapSize(key, w, h) { const r = ccReg(key); return r ? CcLayout.snapSize(r, ccColumns, w, h) : [1, 1]; }
    function ccFits(x, y, w, h, skip) { return CcLayout.fits(ccItems, ccColumns, ccMaxRows, x, y, w, h, skip); }

    // single-step undo, session-only (Android 16's editor has exactly this)
    property string ccUndoJson: ""
    readonly property bool ccCanUndo: ccUndoJson !== ""
    function _ccWrite(items, cols) {
        ccUndoJson = ccLayout;
        ccLayout = JSON.stringify({ v: 2, columns: cols, items: items });
    }
    function ccUndo() {
        if (!ccCanUndo) return;
        const prev = ccUndoJson;
        ccUndoJson = "";
        ccLayout = prev;
    }

    // Every mutation returns true if it was applied. A false means "doesn't fit". Nothing
    // is ever dropped silently; the editor shows the refusal instead.
    function ccPlace(key, x, y, w, h) {
        const cur = ccItem(key);
        if (!cur && !ccReg(key)) return false;
        const sz = ccSnapSize(key, w, h);
        const next = CcLayout.place(ccItems, ccColumns, ccMaxRows, key, x, y, sz[0], sz[1]);
        if (!next || next.length < (cur ? ccItems.length : ccItems.length + 1)) return false;
        _ccWrite(next, ccColumns);
        return true;
    }
    function ccResize(key, w, h) {
        const cur = ccItem(key);
        if (!cur) return false;
        const sz = ccSnapSize(key, w, h);
        // keep the top-left, but pull back inside the grid if the new size would poke out
        const x = Math.min(cur.x, ccColumns - sz[0]);
        const y = Math.min(cur.y, ccMaxRows - sz[1]);
        return ccPlace(key, x, y, sz[0], sz[1]);
    }
    function ccNudge(key, dx, dy) {
        const cur = ccItem(key);
        if (!cur) return false;
        return ccPlace(key, cur.x + dx, cur.y + dy, cur.w, cur.h);
    }
    function ccRemove(key) {
        if (!ccItem(key)) return false;
        _ccWrite(ccItems.filter(i => i.key !== key), ccColumns);
        return true;
    }
    // add at (x,y) if given, else at the first free footprint (iOS: "lands at the first free spot")
    function ccAdd(key, x, y) {
        const r = ccReg(key);
        if (!r || ccItem(key)) return false;
        const sz = CcLayout.resolveSize(r.def, ccColumns);
        if (x === undefined || y === undefined) {
            const spot = CcLayout.firstFree(ccItems, ccColumns, ccMaxRows, sz[0], sz[1], null, 0, 0);
            if (!spot) return false;
            x = spot.x; y = spot.y;
        }
        return ccPlace(key, x, y, sz[0], sz[1]);
    }
    function ccTidy() { _ccWrite(CcLayout.tidy(ccItems, ccColumns, ccMaxRows), ccColumns); return true; }
    function ccReset() { _ccWrite(CcLayout.defaults(ccRegistry, 7, CcLayout.maxRowsFor(ccContentW, 7, ccGap, ccMaxPx)), 7); return true; }
    // refused when the current layout would not survive the new cell budget
    function ccSetColumns(n) {
        n = Math.max(ccMinColumns, Math.min(ccMaxColumns, n | 0));
        if (n === ccColumns) return true;
        const rowsAt = CcLayout.maxRowsFor(ccContentW, n, ccGap, ccMaxPx);
        const next = CcLayout.normalize(ccItems, ccRegistry, n, rowsAt);
        if (next.length < ccItems.length) return false;
        _ccWrite(next, n);
        return true;
    }

    FileView {
        path: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/quickshell/settings.json`
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter() // persist changes back to disk (e.g. a wallpaper pick)

        JsonAdapter {
            id: adapter
            // bar / island
            property int barHeight: 32
            // glass
            property bool blur: true
            property int glassOpacity: 72
            property int glassStrongOpacity: 86
            property int rimAlpha: 12
            property int selectionAlpha: 8
            property int hyprGapsIn: 6
            property int hyprRounding: 10
            property string wallpaperDir: ""
            property bool notchMode: false
            property int notchFlare: 14
            property int islandCollapsedWidth: 150
            property int islandExpandedHeight: 120
            property int islandMinWidth: 500
            property int islandGap: 8
            property int islandPadding: 2
            property int islandRadius: 22
            property int islandRadiusOpen: 32
            property int hyprGapsOut: 12
            property int gameBarHeight: 50
            property int gameClusterGap: 180
            // media
            property int mediaTitleWidth: 104
            property int mediaArtSize: 90
            property bool mediaShowAlbum: true
            property bool mediaShowArtist: true
            property bool mediaShowTransport: true
            property bool mediaScrollSwitch: true
            // clock
            property bool clockSeconds: false
            property bool clock24h: true
            property bool clockDots: true
            property bool clockStatus: true
            // expanded island
            property bool islandWorkspaces: true
            property bool islandStatus: true
            property bool islandMedia: true
            // panels
            property int launcherWidth: 700
            property int launcherRowHeight: 44
            property int launcherMaxRows: 8
            property int controlCenterWidth: 568
            property int calendarWidth: 360
            property int wallpaperPickerWidth: 1040
            property int notificationWidth: 480
            property int osdWidth: 340
            // notifications
            property int notifTimeout: 2000
            property int notifTimeoutCritical: 6000
            property bool notifShowBody: true
            property int notifHistoryHeight: 200
            // osd
            property int osdTimeout: 1500
            property int hudTimeout: 1500
            property int osdBarHeight: 6
            property int volumeStep: 5
            // calendar
            property int weekStartsOn: 0
            property int calendarCellHeight: 32
            property bool calendarShowAdjacent: true
            // lock
            property int lockBlur: 64
            property int lockDim: 22
            property int lockShotQuality: 85
            property bool lockShowDots: false
            property int caretBlink: 580
            // motion
            property bool reducedMotion: false
            property int motionSpring: 400
            property int motionEffects: 230
            property int motionFast: 140
            property int motionBounce: 56
            // appearance
            property int fontSize: 14
            property string wallpaper: ""
            property string fontBody: "Geist"
            property string fontDisplay: "Geist"
            property int radiusSmall: 10
            property int radiusMedium: 14
            property int radiusLarge: 22
            property bool screenCorners: true
            property int screenCornerRadius: 14
            property string accentOverride: ""
            property bool colorBurst: false
            property int surfaceTint: 5          // % ; surfaceBase step off black
            property int spacingUnit: 4
            property int iconSize: 18
            property int iconStroke: 22          // x10 (2.2)
            property int hairlineAlpha: 14       // %
            property int inkDimAlpha: 60         // %
            property int inkFaintAlpha: 35       // %
            property int fillLowAlpha: 6         // %
            property int fillHighAlpha: 13       // %
            property int scrimOpacity: 50        // %
            property int shadowOpacity: 14       // %
            property int shadowBlur: 100         // %
            property int shadowOffsetY: 10
            property int shadowSpread: 80
            // system
            property int brightnessStep: 5
            property int brightnessPoll: 2000
            property int batteryLowThreshold: 20
            property int nightLightTemp: 3000
            property int wallpaperFade: 450
            // control center layout (see ccRegistry / CcLayout.js)
            property string ccLayout: ""
        }
    }
}
