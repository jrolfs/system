import QtQuick
import QtQuick.Shapes
import "../theme"

// Wi-Fi icon drawn from shapes that also works as a signal meter: a dot + three arcs,
// each lit once `strength` clears its threshold, dim otherwise. `strength` takes either
// 0..1 or 0..100. Colors are themeable so it can sit inside an accent tile. Geometry's
// tuned so the fan's OPTICAL centre lands on the box centre (the dot + lower arcs are
// heavy), so it lines up with its sibling icons under verticalCenter.
Item {
    id: root

    property real strength: 0          // 0..1 or 0..100
    property bool active: true         // connected / enabled
    property color color: Theme.accent
    property color dimColor: Theme.inkFaint

    implicitWidth: 22
    implicitHeight: 16

    // take either 0..1 or a 0..100 percentage
    readonly property real level: strength > 1 ? strength / 100 : strength

    readonly property real cx: width / 2
    readonly property real cy: height - 4   // lifts the fan so its optical centre sits ≈ box centre

    function arcColor(t) {
        return (active && root.level >= t) ? root.color : root.dimColor;
    }

    // base dot, lit whenever connected
    Rectangle {
        width: 4; height: 4; radius: 2
        x: root.cx - 2
        y: root.cy - 2
        color: root.active ? root.color : root.dimColor
    }

    Shape {
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer   // analytic GPU AA, smooth thin arcs (the default renderer triangulates and looks jaggy as hell)

        // inner arc, any signal at all
        ShapePath {
            strokeColor: root.arcColor(0.01); strokeWidth: 2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: 3.5; radiusY: 3.5; startAngle: 220; sweepAngle: 100 }
        }
        // middle arc
        ShapePath {
            strokeColor: root.arcColor(0.38); strokeWidth: 2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: 7; radiusY: 7; startAngle: 220; sweepAngle: 100 }
        }
        // outer arc, strong signal
        ShapePath {
            strokeColor: root.arcColor(0.68); strokeWidth: 2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: 10.5; radiusY: 10.5; startAngle: 220; sweepAngle: 100 }
        }
    }
}
