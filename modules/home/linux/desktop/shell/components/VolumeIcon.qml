import QtQuick
import QtQuick.Shapes
import "../theme"

// Volume icon that tracks the level: a speaker, plus waves that fade in as the level
// rises (one wave above ~0%, a second above ~50%), or an X when muted. The wave and X
// transitions animate on alpha, so the icon reacts as you change the volume.
Item {
    id: root

    property real level: 0       // 0..1
    property bool muted: false
    property color color: Theme.inkPrimary
    property real size: Theme.iconSize

    implicitWidth: size
    implicitHeight: size

    readonly property real lv: Math.max(0, Math.min(1, level))
    // each part's visibility, animated
    property real w1: (!muted && lv > 0.001) ? 1 : 0
    property real w2: (!muted && lv >= 0.5) ? 1 : 0
    property real xo: muted ? 1 : 0
    Behavior on w1 { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
    Behavior on w2 { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
    Behavior on xo { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }

    Shape {
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { xScale: root.size / 24; yScale: root.size / 24 }

        // speaker body: always drawn, filled
        ShapePath {
            fillColor: root.color; strokeColor: "transparent"; strokeWidth: 0
            PathSvg { path: "M4,10 H7 L11,6 V18 L7,14 H4 Z" }
        }
        // wave 1 (small)
        ShapePath {
            fillColor: "transparent"; strokeColor: Theme.alpha(root.color, root.w1); strokeWidth: 2.2; capStyle: ShapePath.RoundCap
            PathSvg { path: "M14,9.5 a3.5,3.5 0 0,1 0,5" }
        }
        // wave 2 (large)
        ShapePath {
            fillColor: "transparent"; strokeColor: Theme.alpha(root.color, root.w2); strokeWidth: 2.2; capStyle: ShapePath.RoundCap
            PathSvg { path: "M16.5,7 a7,7 0 0,1 0,10" }
        }
        // mute X
        ShapePath {
            fillColor: "transparent"; strokeColor: Theme.alpha(root.color, root.xo); strokeWidth: 2.2; capStyle: ShapePath.RoundCap
            PathSvg { path: "M14.5,9.5 L19.5,14.5 M19.5,9.5 L14.5,14.5" }
        }
    }
}
