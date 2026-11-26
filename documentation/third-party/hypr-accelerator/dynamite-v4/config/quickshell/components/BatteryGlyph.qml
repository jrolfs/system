import QtQuick
import QtQuick.Shapes
import "../theme"

// Battery indicator. Custom-drawn, but NOT invented — the proportions are lifted from
// Material Symbols Rounded `battery_android` (rendered large and measured), so it sits
// correctly beside the rest of the icon set:
//
//     body                19.50u x 12.00u
//     terminal nub         1.50u x 4.90u, 1.00u clear of the body, vertically centred
//     total                22.00u x 12.00u
//
// Three deliberate departures, each for a reason:
//
//   · the corners go from Material's 2.6u to 4.0u, so the shape rhymes with the rounded
//     island it sits inside. NOT a full pill (6u), which was tried and rejected: at this size
//     a fully-rounded body stops reading as a battery, the nub looks detached from it, and a
//     part-filled bar inside it looks like the knob of a toggle switch. 4u is as round as it
//     goes while still obviously being a battery;
//   · the fill's own radius is kept low (1.4u) for the same reason — at a pill radius the bar
//     is narrower than it is tall below ~60% and renders as a circle, which is what made it
//     read as a switch;
//   · the stroke drops from Material's 2.0u to 1.6u. Same 24-unit grid as Icon.qml (2.2u),
//     but this shape is only 12u tall where those are ~18-20u, so an equal stroke reads far
//     denser on it. Thinning it puts the visual weight back in line next to SF Pro;
//   · the fill is CONTINUOUS. The font family only ships seven discrete steps, so 63% had to
//     round to the nearest sixth; here it's drawn at 63%.
//
// Charging keeps a real bolt rather than degrading to a colour swap — it's drawn light so it
// reads both over the tinted fill and over the empty part of the shell.
Item {
    id: root

    property real level: 1.0        // 0..1, drawn continuously
    property bool charging: false
    property bool low: false
    property int size: Theme.iconSize   // em-equivalent: the 24-unit grid scales to this

    property color outlineColor: Theme.inkDim      // the grey shell
    property color fillColor: Theme.inkPrimary     // the bright charge bar
    // channel between the fill and the inside of the outline
    property real gap: Math.max(1, Math.min(2, size * 0.06))
    // corner radii in grid units, tunable: Material ships 2.6u, a full pill is 6u
    property real bodyRadiusU: 4.0
    property real fillRadiusU: 1.4

    readonly property real u: size / 24
    readonly property real pct: Math.max(0, Math.min(1, level))

    implicitWidth: 22 * u
    implicitHeight: 12 * u

    // body. Qt draws a Rectangle's border INSIDE its bounds, so the bounds are the outer
    // edge and what's left after the stroke is the cavity.
    Rectangle {
        id: body
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 19.5 * root.u
        height: 12 * root.u
        radius: Math.min(height / 2, root.bodyRadiusU * root.u)
        color: "transparent"
        border.width: Math.max(1, 1.6 * root.u)
        border.color: root.outlineColor
        antialiasing: true
    }

    // the charge — width tracks `level` continuously
    Rectangle {
        id: fill
        readonly property real inset: body.border.width + root.gap
        x: body.x + inset
        anchors.verticalCenter: body.verticalCenter
        height: Math.max(0, body.height - inset * 2)
        width: Math.max(0, (body.width - inset * 2) * root.pct)
        radius: Math.min(height / 2, root.fillRadiusU * root.u)
        color: root.low ? Theme.bad : root.charging ? Theme.good : root.fillColor
        antialiasing: true
        visible: width > 0.3
        Behavior on width { NumberAnimation { duration: Theme.dur(Theme.dBase); easing.type: Theme.easeOut } }
        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
    }

    // charging bolt, centred on the body. Material's own bolt outline, normalised to a
    // 10x18 box and scaled to fit the cavity.
    Shape {
        id: bolt
        visible: root.charging
        readonly property real k: (7.6 * root.u) / 18     // target height / path height
        width: 10 * k
        height: 18 * k
        anchors.centerIn: body
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { xScale: bolt.k; yScale: bolt.k }
        ShapePath {
            fillColor: Theme.inkPrimary
            strokeWidth: -1
            PathSvg { path: "M 4,18 L 4,11 L 0,11 L 6,0 L 6,7 L 10,7 Z" }
        }
    }

    // terminal nub, rounded to match
    Rectangle {
        anchors.left: body.right
        anchors.leftMargin: 1 * root.u
        anchors.verticalCenter: body.verticalCenter
        width: 1.5 * root.u
        height: 4.9 * root.u
        radius: width / 2
        color: root.outlineColor
        antialiasing: true
    }
}
