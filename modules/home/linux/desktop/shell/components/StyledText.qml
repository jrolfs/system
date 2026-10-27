import QtQuick
import "../theme"

// Theme-aware text on the Obsidian type scale. Set `variant` to pick the role (display
// uses the mono display face, the rest use the body face). Callers can still override
// font.pixelSize / color directly: explicit assignment wins, so existing call sites
// keep working.
Text {
    id: root

    // display | header | title | body | label | caption
    property string variant: "body"

    color: Theme.inkPrimary
    font.family: variant === "display" ? Theme.fontDisplay : Theme.fontBody
    font.pixelSize: variant === "display" ? Theme.fsDisplay
        : variant === "title" ? Theme.fsTitle
        : variant === "header" ? Theme.fsHeader
        : variant === "label" ? Theme.fsLabel
        : variant === "caption" ? Theme.fsCaption
        : Theme.fsBody
    font.weight: (variant === "display" || variant === "title" || variant === "header") ? Theme.wMedium : Theme.wRegular
    // headers get tightened tracking; everything else stays at natural spacing
    font.letterSpacing: variant === "header" ? Theme.headerTracking : 0
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter

    // Vertical centring by CAP HEIGHT (patterns.md #41). Box-centring a single-line label
    // beside a control floats its capitals off the control's centre line: the box carries
    // the descender space and the native baseline rounds to a whole pixel, so a word like
    // "Wi-Fi" sat up to ~0.7px off the disc and toggle beside it, which is visible from
    // close up. Set `capCentreIn` to the row (or the control) instead of anchoring
    // verticalCenter, and the cap centre lands on its centre line exactly, at any font
    // size. Applied once at creation, so the anchor is never toggled at runtime (#23).
    property Item capCentreIn: null
    FontMetrics { id: capFm; font: root.font }
    anchors.baselineOffset: capFm.capitalHeight / 2
    Component.onCompleted: if (capCentreIn) anchors.baseline = capCentreIn.verticalCenter
}
