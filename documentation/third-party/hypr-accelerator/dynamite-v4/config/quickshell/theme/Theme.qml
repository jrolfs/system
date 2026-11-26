pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Design tokens. COLORS come live from ~/.config/quickshell/colors.json, which wallust
// rewrites on every theme switch (curated `cs`, dynamic `run`, or builtin `theme`).
// Read through FileView, so value changes hot-reload and the shell restyles WITHOUT a
// restart. Falls back to the Ariadne palette when the file's missing. The non-color
// tokens (spacing / typography / motion) live down here.
Singleton {
    id: root

    FileView {
        path: `${Quickshell.env("HOME")}/.config/quickshell/colors.json`
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: pal
            property string background: "#040e0d"
            property string foreground: "#f5e2c5"
            property string cursor: "#f5e2c5"
            property string color0: "#040e0d"
            property string color1: "#ff6048"
            property string color2: "#7ad9a8"
            property string color3: "#f5cd5b"
            property string color4: "#5fc8d4"
            property string color5: "#e89aa8"
            property string color6: "#3dd1b0"
            property string color7: "#c4b09a"
            property string color8: "#3a1a35"
            property string color9: "#ff6048"
            property string color10: "#7ad9a8"
            property string color11: "#f5cd5b"
            property string color12: "#5fc8d4"
            property string color13: "#e89aa8"
            property string color14: "#3dd1b0"
            property string color15: "#f5e2c5"
        }
    }

    // color helpers
    // Blend two colors (t=0 → a, t=1 → b). We derive the surface shades from the
    // palette this way so they adapt to any scheme, curated or dynamic.
    function mix(a, b, t) {
        return Qt.rgba(a.r * (1 - t) + b.r * t, a.g * (1 - t) + b.g * t, a.b * (1 - t) + b.b * t, 1);
    }
    // Same color at a given alpha (ink/glass derived from fg, so it adapts to light themes).
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    // Perceived luminance 0..1, used to pick readable ink on the accent.
    function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b; }

    // palette (straight from colors.json)
    readonly property color background: pal.background
    readonly property color foreground: pal.foreground
    readonly property color fg: foreground
    // the accent: the scheme's by default, or the user's override from Settings
    readonly property color schemeAccent: pal.color6
    readonly property bool accentOverridden: /^#[0-9a-fA-F]{6}$/.test(Config.accentOverride)
    readonly property color accent: accentOverridden ? Config.accentOverride : schemeAccent
    // Color burst: each GROUP of surfaces takes its own colour of the scheme's palette
    // instead of everything wearing the one accent. A group is one coloured thing: the
    // workspace row, the status cluster, the control center's toggles, its sliders, its
    // media card, the launcher, the calendar, the polkit prompt. A sheet inherits its
    // tile's group. `hue(group)` is the accent unless burst is on; an unknown group hashes
    // to a stable slot so a new surface still gets one colour of its own.
    readonly property bool burst: Config.colorBurst
    readonly property var hues: [pal.color1, pal.color2, pal.color3, pal.color4, pal.color5, pal.color6]
    readonly property var hueSlots: ({ workspaces: 5, status: 3, toggles: 4, sliders: 1, media: 0,
                                      launcher: 2, calendar: 0, polkit: 0, notifications: 2 })
    function hue(group) {
        if (!burst) return accent;
        let s = hueSlots[group];
        if (s === undefined) { s = 0; for (let k = 0; k < group.length; k++) s = (s * 31 + group.charCodeAt(k)) % 6; }
        return hues[s];
    }
    function inkOn(c) { return lum(c) > 0.55 ? "#0b0b0b" : "#f6f6f6"; }

    readonly property color red: pal.color1
    readonly property color green: pal.color2
    readonly property color yellow: pal.color3
    readonly property color orange: pal.color3
    readonly property color blue: pal.color4
    readonly property color purple: pal.color5
    readonly property color aqua: pal.color6
    readonly property color grey0: pal.color8
    readonly property color grey2: pal.color7

    // DESIGN.md "Obsidian" token system. Build new UI from these; the legacy
    // tokens below stick around for back-compat 'til every surface is migrated.

    // color roles
    readonly property color accentDeep: Qt.darker(accent, 1.18)          // for pressed/active
    readonly property color onAccent: lum(accent) > 0.55 ? "#0b0b0b" : "#f6f6f6" // readable ink on accent

    // Scheme polarity. "Light" means the text is darker than the paper — the one test that
    // holds for any scheme, curated or dynamic, with no magic luminance cutoff to mis-fire.
    readonly property bool isLight: lum(background) > lum(foreground)

    // The shell (island + all its surfaces) is solid BLACK on a dark scheme, so elevation is
    // built from relatives of black, NOT the wallpaper-tinted `background`: near-black greys
    // that carry a whisper of the fg hue so they still fit the scheme. `background` stays
    // palette-derived for the true desktop base (wallpaper fallback). Accents are untouched.
    //
    // A LIGHT scheme (e-ink) flips the base to the scheme's own paper tone. The same
    // mix-toward-ink elevation steps then DARKEN it, which is how a light UI reads depth too.
    // Black was hardcoded here before, and under e-ink's #0a0a0a foreground that collapsed
    // ink and surface into the same near-black: every panel rendered as black text on black.
    readonly property color base: isLight ? background : "#000000"

    // a RECESSED fill (slider troughs, wells): sinks toward black on dark, toward ink on light
    readonly property color sunken: isLight ? alpha(foreground, 0.08) : Qt.rgba(0, 0, 0, 0.45)

    // surface fills (base / panel / modal): opaque near-black elevation steps. The step size
    // is user-tunable (settings → Appearance → "Surface lift"); each level is roughly double
    // the one below so the three stay distinguishable at any setting.
    readonly property real surfaceStep: Config.surfaceTint / 100
    readonly property color surfaceBase: mix(base, foreground, surfaceStep)
    readonly property color surfacePanel: mix(base, foreground, surfaceStep * 2)
    readonly property color surfaceOverlay: mix(base, foreground, surfaceStep * 3.3)


    // ink (text/icon), derived from fg so it adapts to light schemes
    readonly property color inkPrimary: foreground
    readonly property color inkDim: alpha(foreground, Config.inkDimAlpha / 100)
    readonly property color inkFaint: alpha(foreground, Config.inkFaintAlpha / 100)

    // flat fill tints (solid-looking, NOT glass, nothing blurs behind them) +
    // hairline (borders/dividers). Derived from fg so they adapt to light schemes.
    readonly property color fillLow: alpha(foreground, Config.fillLowAlpha / 100)
    readonly property color fillHigh: alpha(foreground, Config.fillHighAlpha / 100)
    readonly property color hairline: alpha(foreground, Config.hairlineAlpha / 100)
    // the RIM on control-center tiles: a step QUIETER than a divider hairline. A tile's edge
    // only has to hint at where the surface ends against the black island; at full hairline
    // strength it read as an outline.
    readonly property color rim: alpha(foreground, Config.hairlineAlpha / 100 * 0.6)
    // legacy aliases (pre-flat name); move call sites over to fill* over time
    readonly property color glassLow: fillLow
    readonly property color glassHigh: fillHigh
    // flat translucent black dim behind modals (intentionally not palette-tinted; no blur)
    readonly property color scrim: Qt.rgba(0, 0, 0, Config.scrimOpacity / 100)

    // semantic (used rarely: battery low / errors / destructive confirms)
    readonly property color good: pal.color2
    readonly property color warn: pal.color3
    readonly property color bad: pal.color1

    // layering. Stacked surfaces are told apart by the fill step
    // (surfaceBase → surfacePanel → surfaceOverlay) + a hairline, plus the scrim
    // for modals, never by stacked shadows. The ONE depth cue is a single subtle
    // drop shadow on FLOATING surfaces (the island + popout panels) so they lift
    // off the wallpaper. Tokenized here, used identically everywhere. (No blur, ever.)
    readonly property color shadow: Qt.rgba(0, 0, 0, Config.shadowOpacity / 100) // floating-surface drop shadow
    readonly property real  shadowBlur: Config.shadowBlur / 100  // MultiEffect blur (0..1)
    readonly property int   shadowY: Config.shadowOffsetY        // vertical offset (px)
    readonly property int   shadowBlurMax: Config.shadowSpread   // MultiEffect blurMax (px)

    // radii (all user-tunable from settings → Appearance)
    readonly property int rSm: Config.radiusSmall     // inner controls
    readonly property int rMd: Config.radiusMedium    // cards / inner
    readonly property int rLg: Config.radiusLarge     // surfaces / panels
    readonly property int rXl: Config.radiusLarge + 6 // Material-You tiles / thick sliders
    readonly property int rPill: 999
    // the floating island's our signature surface, so it gets its own bigger corners
    readonly property int rIsland: Config.islandRadius          // collapsed pill
    readonly property int rIslandOpen: Config.islandRadiusOpen  // expanded card

    // spacing (base unit 4)
    readonly property int s1: Config.spacingUnit
    readonly property int s2: Config.spacingUnit * 2
    readonly property int s3: Config.spacingUnit * 3
    readonly property int s4: Config.spacingUnit * 4
    readonly property int s5: Config.spacingUnit * 6
    readonly property int s6: Config.spacingUnit * 8

    // typography
    readonly property string fontDisplay: Config.fontDisplay  // numerals / data labels
    readonly property string fontBody: Config.fontBody         // everything else
    readonly property string fontGlyph: "JetBrainsMono Nerd Font Propo" // nerd-font icons
    readonly property int fontSize: Config.fontSize                 // user-tunable (settings)
    // type scale (relative to fontSize so the settings slider scales it all)
    readonly property int fsDisplay: Math.round(fontSize * 2.4)
    readonly property int fsTitle: Math.round(fontSize * 1.35)
    readonly property int fsHeader: Math.round(fontSize * 1.2)   // menu/section headers, a touch under title
    readonly property real headerTracking: -0.4                  // tightened letter-spacing for headers
    readonly property int fsBody: fontSize
    readonly property int fsLabel: Math.round(fontSize * 0.9)
    readonly property int fsCaption: Math.round(fontSize * 0.78)
    // notch clock, scales with fontSize so the settings slider drives it too
    readonly property int fsClock: fontSize + 2       // collapsed time
    readonly property int fsClockBig: fontSize + 9    // expanded "hero" time
    // weights (400/500 only)
    readonly property int wRegular: 400
    readonly property int wMedium: 500
    readonly property int wSemiBold: 600

    // iconography
    readonly property int iconSize: Config.iconSize
    readonly property real iconStroke: Config.iconStroke / 10

    // MOTION. Every curve here is a real SPRING: the step response of a damped harmonic
    // oscillator, sampled and handed to Qt as a cubic bezier spline. That's what gives motion
    // the iOS feel — it starts from rest, accelerates, then SETTLES, overshooting a touch and
    // easing back when it's underdamped. A plain ease-out bezier can't do that: it creeps up
    // on the target from one side and stops dead.
    //
    // springCurve(zeta) builds one. zeta is the DAMPING RATIO:
    //   1.0 = critically damped, no overshoot  ·  < 1 = overshoots, then settles back
    //   0.85 subtle · 0.72 iOS-ish · 0.55 pronounced bounce
    // The decay is picked so the response has settled to ~0.1% by the END of the animation's
    // duration, so the curve finishes flat instead of being cut off mid-oscillation.
    // NOTE ON SEGMENT COUNT: Qt's bezier-spline solver CRASHES on an overshooting spline once
    // the segments get too short in x (12+ segments took the whole shell down; 10 was the last
    // that survived). 8 is the safe ceiling and still tracks the true spring to within ~1% of
    // its travel, which is invisible. Do NOT raise it.
    function springCurve(zeta, segments) {
        var n = segments || 8;
        var z = Math.max(0.4, Math.min(1.0, zeta));           // clamp: a hand-edited config must
        var w = 6.5 / z;                                      // never divide by zero into a NaN curve
        var under = z < 0.999;
        var wd = under ? w * Math.sqrt(1 - z * z) : 0;        // damped frequency
        var k = under ? (z * w / wd) : 0;
        function val(t) {
            return under ? 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + k * Math.sin(wd * t))
                         : 1 - (1 + w * t) * Math.exp(-w * t);
        }
        function slope(t) {
            return under ? (w * w / wd) * Math.exp(-z * w * t) * Math.sin(wd * t)
                         : w * w * t * Math.exp(-w * t);
        }
        // Sample it, then turn each span (value + tangent at both ends) into a cubic bezier
        // segment, control points a third of the step along the tangent. Qt walks the spline
        // as the easing curve, so the whole damped response survives, overshoot and all.
        var pts = [], h = 1 / n;
        for (var i = 0; i < n; i++) {
            var last = i === n - 1;
            var t0 = i * h, t1 = last ? 1 : (i + 1) * h;
            var y0 = val(t0), y1 = last ? 1 : val(t1);        // force the end to land exactly on 1
            var s0 = slope(t0), s1 = last ? 0 : slope(t1);
            pts.push(t0 + h / 3, y0 + s0 * h / 3,
                     t1 - h / 3, y1 - s1 * h / 3,
                     t1, y1);
        }
        return pts;
    }

    // spatial (position / size / scale: notch, panels, reflow) — the bouncy one. Bounce is
    // user-tunable (settings → Motion); 0% is dead flat, 100% is springy as it gets.
    // The three base durations are user-tunable too; the derived ones scale with the spring
    // so speeding the shell up moves everything together.
    readonly property real springDamping: 1.0 - (Config.motionBounce / 100) * 0.5
    readonly property var springBezier: springCurve(springDamping, 8)
    readonly property int dSpring: Config.motionSpring
    // effects (opacity / colour: fades, borders) — critically damped ON PURPOSE. A fade that
    // overshoots just clamps at 0/1 and lands early, which reads as an abrupt cut, not a bounce.
    readonly property var effectsBezier: springCurve(1.0, 8)
    readonly property int dEffects: Config.motionEffects
    readonly property int easeOut: Easing.OutCubic       // standard
    readonly property int easeInOut: Easing.InOutCubic
    readonly property int dFast: Config.motionFast       // micro / hover
    readonly property int dBase: Math.round(dSpring * 0.7)
    readonly property int dExpand: Math.round(dSpring * 1.2)
    readonly property int dEnter: Math.round(dSpring * 1.5)
    readonly property int stagger: Math.round(dSpring * 0.225)
    readonly property bool reducedMotion: Config.reducedMotion
    // Game Mode strips the drop shadows (an FBO + a big blur per surface, every frame while
    // anything moves), which is where the GPU cost measurably was. It no longer touches the
    // durations: the shell kept animating and games did not notice, while the shell at zero
    // duration felt broken. Set from shell.qml so theme/ needn't import services/.
    property bool gameMode: false
    readonly property bool shadows: !gameMode
    // collapse durations when reduced motion is on
    function dur(d) { return reducedMotion ? 0 : d; }

    // Legacy tokens (pre-Obsidian), still read by un-migrated components.
    // Migrate each surface to the tokens above, then prune these.
    readonly property color bg0: background
    readonly property color surface: surfaceBase
    readonly property color surfaceRaised: surfacePanel
    readonly property color subtext: inkDim
    readonly property int spacing: s2
    readonly property int radius: rSm
    readonly property string fontFamily: fontBody
    readonly property int animDuration: dFast
}
