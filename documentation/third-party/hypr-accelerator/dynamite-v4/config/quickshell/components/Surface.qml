import QtQuick
import QtQuick.Effects
import "../theme"

// Flat surface: a solid themed fill plus a 1px hairline edge. Layering shows through the
// fill step (surfaceBase → surfacePanel → surfaceOverlay) and the hairline. Set
// `floating: true` to add the one depth cue we allow: a subtle drop shadow (the
// Theme.shadow* tokens, no blur) cast by the background shape only, so popout panels
// lift off the wallpaper and read as siblings of the notch. Put content in as children;
// they sit ON TOP of the (maybe shadowed) shape, never inside it.
Item {
    id: root

    property color fill: Theme.surfacePanel
    property int radius: Theme.rLg
    property bool hairline: true
    property color hairlineColor: Theme.hairline
    property bool floating: false   // adds the subtle floating drop shadow

    default property alias content: holder.data

    // the shape (filled rounded rect + hairline). Shadowed when floating, and since it
    // has NO children, the shadow comes off the shape alone, not the content.
    Rectangle {
        id: bgShape
        anchors.fill: parent
        radius: root.radius
        color: root.fill
        border.width: root.hairline ? 1 : 0
        border.color: root.hairlineColor
        antialiasing: true
        layer.enabled: root.floating && Theme.shadows
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowBlur: Theme.shadowBlur
            shadowVerticalOffset: Theme.shadowY
            blurMax: Theme.shadowBlurMax
            autoPaddingEnabled: true
        }
    }

    // content layer, on top of the shape and outside the shadowed layer
    Item { id: holder; anchors.fill: parent }
}
