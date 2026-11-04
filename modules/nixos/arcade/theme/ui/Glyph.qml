import QtQuick 2.15
import QtQuick.Shapes 1.15
import "."

// The shell's icons (components/Icon.qml), drawn the same way: an SVG path in
// a 24-unit box, stroked with round caps or filled. The face buttons are
// PlayStation's, since that's the pad on the couch. Qt 5's shapes have no
// curve renderer to antialias with, so each glyph renders through a
// multisampled layer instead.
Item {
    id: root

    property string name: ""
    property real size: Theme.iconSize
    property color color: Theme.inkPrimary
    // Floored so the rendered stroke never thins past about 1.2px.
    property real strokeWidth: Math.max(Theme.iconStroke, 1.2 * 24 / Math.max(1, size))

    readonly property var paths: ({
        "cross":      { d: "M7,7 L17,17 M17,7 L7,17", filled: false },
        "circle":     { d: "M5.5,12 a6.5,6.5 0 1,0 13,0 a6.5,6.5 0 1,0 -13,0", filled: false },
        "square":     { d: "M6.5,6.5 H17.5 V17.5 H6.5 Z", filled: false },
        "triangle":   { d: "M12,5.5 L18.5,17 H5.5 Z", filled: false },
        "heart":      { d: "M12,20 C12,20 3.5,14.6 3.5,9.2 A4.2,4.2 0 0,1 12,7.4 A4.2,4.2 0 0,1 20.5,9.2 C20.5,14.6 12,20 12,20 Z", filled: true },
        "play":       { d: "M8,5 L19,12 L8,19 Z", filled: true },
        "controller": { d: "M6,9.5 H18 a2.5,2.5 0 0,1 2.5,2.5 v1 a2.5,2.5 0 0,1 -2.5,2.5 H6 a2.5,2.5 0 0,1 -2.5,-2.5 v-1 a2.5,2.5 0 0,1 2.5,-2.5 Z M8,11.5 V14.5 M6.5,13 H9.5 M15,12.5 h0 M17,14 h0", filled: false },
        "person":     { d: "M12,4.3 a3.9,3.9 0 1,0 0.01,0 Z M4.8,20 C4.8,14.6 8,12.9 12,12.9 C16,12.9 19.2,14.6 19.2,20 Z", filled: true },
        "clock":      { d: "M4,12 a8,8 0 1,0 16,0 a8,8 0 1,0 -16,0 M12,7.5 V12 L15,14", filled: false }
    })
    readonly property var path: paths[name] || { d: "", filled: false }

    implicitWidth: size
    implicitHeight: size

    layer.enabled: true
    layer.samples: 8
    layer.smooth: true

    Shape {
        width: 24
        height: 24
        transform: Scale { xScale: root.size / 24; yScale: root.size / 24 }

        ShapePath {
            fillColor: root.path.filled ? root.color : "transparent"
            strokeColor: root.path.filled ? "transparent" : root.color
            // -1 turns stroking off outright, which a transparent stroke with
            // a width doesn't.
            strokeWidth: root.path.filled ? -1 : root.strokeWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.path.d }
        }
    }
}
