pragma Singleton
import QtQuick 2.15
import "Generated.js" as Generated
import "Spring.js" as Spring

// Design tokens: the desktop shell's Theme.qml, carried to Qt 5 and a TV. The
// roles and their derivations are the shell's, so a pane, a row or a keycap
// here is the one the shell draws. The numbers come from Generated.js, which
// package.nix writes from modules/theme, the same files the shell reads.
QtObject {
    id: root

    readonly property var palette: Generated.values.palette
    readonly property var style: Generated.values.style
    readonly property var station: Generated.values.station
    readonly property var labels: Generated.values.labels

    // Set by theme.qml to the window's size. Every length goes through px(),
    // which maps the shell's 1920×1080 logical canvas onto the screen and
    // scales it up for the couch.
    property real screenWidth: 1920
    property real screenHeight: 1080
    readonly property real unit: screenHeight / 1080 * station.scale
    function px(value) { return Math.round(value * unit); }

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    function mix(a, b, t) {
        return Qt.rgba(a.r * (1 - t) + b.r * t, a.g * (1 - t) + b.g * t, a.b * (1 - t) + b.b * t, 1);
    }
    function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b; }

    readonly property color bgDim: palette.bg_dim
    readonly property color bg0: palette.bg0
    readonly property color bg1: palette.bg1
    readonly property color bg3: palette.bg3
    readonly property color fg0: palette.fg0
    readonly property color fg1: palette.fg1
    readonly property color grey0: palette.grey0
    readonly property color grey1: palette.grey1
    readonly property color grey2: palette.grey2
    readonly property color red: palette.red
    readonly property color orange: palette.orange
    readonly property color yellow: palette.yellow
    readonly property color green: palette.green
    readonly property color aqua: palette.aqua
    readonly property color blue: palette.blue
    readonly property color purple: palette.purple

    readonly property color foreground: fg0
    readonly property color accent: yellow
    readonly property color onAccent: lum(accent) > 0.55 ? "#0b0b0b" : "#f6f6f6"

    // Each system takes a palette colour of its own, for the monograms that
    // stand in for missing art. Hashed from the shortname, so it never moves.
    readonly property var hues: [red, green, yellow, blue, purple, aqua]
    function hue(key) {
        var name = String(key || "");
        var slot = 0;
        for (var i = 0; i < name.length; i++)
            slot = (slot * 31 + name.charCodeAt(i)) % hues.length;
        return hues[slot];
    }

    // Glass: the pane over the blur, a denser one for something stacked on it,
    // and the faint light rim around both.
    readonly property color base: alpha(bg0, style.glassOpacity / 100)
    readonly property color glassStrong: alpha(bgDim, style.glassStrongOpacity / 100)
    readonly property color rim: alpha(fg1, style.rimAlpha / 100)

    // Elevation on glass is a translucent lift toward the ink, not an opaque step.
    readonly property real surfaceStep: style.surfaceTint / 100
    readonly property color surfaceBase: alpha(foreground, surfaceStep)
    readonly property color surfacePanel: alpha(foreground, surfaceStep * 2)
    readonly property color surfaceOverlay: alpha(foreground, surfaceStep * 3.3)

    readonly property color selection: alpha(foreground, style.selectionAlpha / 100)
    readonly property color inkPrimary: foreground
    readonly property color inkSecondary: grey2
    readonly property color inkDim: alpha(foreground, style.inkDimAlpha / 100)
    readonly property color inkFaint: alpha(foreground, style.inkFaintAlpha / 100)
    readonly property color fillLow: alpha(foreground, style.fillLowAlpha / 100)
    readonly property color fillHigh: alpha(foreground, style.fillHighAlpha / 100)
    readonly property color hairline: alpha(foreground, style.hairlineAlpha / 100)
    readonly property color keycapEdge: alpha(foreground, 0.24)
    readonly property color keycapInk: alpha(foreground, 0.62)
    readonly property color scrim: Qt.rgba(0, 0, 0, style.scrimOpacity / 100)

    readonly property color shadow: Qt.rgba(0, 0, 0, style.shadowOpacity / 100)
    readonly property real shadowBlur: px(style.shadowSpread * style.shadowBlur / 100)
    readonly property real shadowY: px(style.shadowOffsetY)

    readonly property int rSm: px(style.radiusSmall)
    readonly property int rMd: px(style.radiusMedium)
    readonly property int rLg: px(style.radiusLarge)
    readonly property int rXl: px(style.radiusLarge + 6)
    readonly property int rRow: px(style.radiusSmall + 2)
    readonly property int rIsland: px(style.islandRadius)
    readonly property int rIslandOpen: px(style.islandRadiusOpen)

    readonly property int s1: px(style.spacingUnit)
    readonly property int s2: px(style.spacingUnit * 2)
    readonly property int s3: px(style.spacingUnit * 3)
    readonly property int s4: px(style.spacingUnit * 4)
    readonly property int s5: px(style.spacingUnit * 6)
    readonly property int s6: px(style.spacingUnit * 8)
    readonly property int panelPad: px(style.spacingUnit * 5)
    readonly property int hairlineWidth: Math.max(1, px(1))

    readonly property string fontBody: Generated.values.fonts.sans
    readonly property real fontSize: style.fontSize * unit
    readonly property int fsDisplay: Math.round(fontSize * 2.4)
    readonly property int fsTitle: Math.round(fontSize * 1.35)
    readonly property int fsHeader: Math.round(fontSize * 1.2)
    readonly property int fsBody: Math.round(fontSize)
    readonly property int fsLabel: Math.round(fontSize * 0.9)
    readonly property int fsCaption: Math.round(fontSize * 0.78)
    readonly property real headerTracking: -0.4 * unit

    readonly property int rowHeight: px(style.launcherRowHeight)
    readonly property int iconSize: px(style.iconSize)
    readonly property real iconStroke: style.iconStroke / 10

    // Springs for position and size; the critically damped curve for fades,
    // since a fade that overshoots only clamps and lands early.
    readonly property var springBezier: Spring.curve(1.0 - style.motionBounce / 100 * 0.5, 8)
    readonly property var effectsBezier: Spring.curve(1.0, 8)
    readonly property int dSpring: style.motionSpring
    readonly property int dEffects: style.motionEffects
    readonly property int dFast: style.motionFast
    readonly property int dBase: Math.round(dSpring * 0.7)
    readonly property int dEnter: Math.round(dSpring * 1.5)
}
