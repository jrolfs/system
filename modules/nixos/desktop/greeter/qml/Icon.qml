import QtQuick
import QtQuick.Shapes

// The few glyphs the greeter draws, as paths in a 24x24 box, the same way the
// shell's components/Icon.qml does it. Shapes rather than an icon font, so
// nothing on the login screen depends on which fonts happen to be installed.
Item {
    id: root

    property string name: ""
    property real size: 16
    property color color: Colors.fg1
    property real strokeWidth: 1.9

    implicitWidth: size
    implicitHeight: size

    readonly property var _icons: ({
        "arrow":   { d: "M5,12 H19 M13,6 L19,12 L13,18", filled: false },
        "power":   { d: "M12,3.5 V11.5 M7,6.5 A7.5,7.5 0 1,0 17,6.5", filled: false },
        "restart": { d: "M19.5,12 A7.5,7.5 0 1,1 16.6,6 M19.5,4 V8.5 H15", filled: false },
        "suspend": { d: "M20,13.5 A8.5,8.5 0 1,1 10.5,4 A6.5,6.5 0 0,0 20,13.5 Z", filled: true }
    })
    readonly property var _def: _icons[name] ?? ({ d: "", filled: false })

    // The curve renderer for fills only: it drops thin strokes entirely, which
    // is how the power and restart glyphs went missing. Strokes take the
    // geometry renderer, multisampled for the edges it doesn't smooth itself.
    layer.enabled: !_def.filled
    layer.samples: 4

    Shape {
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: root._def.filled ? Shape.CurveRenderer : Shape.GeometryRenderer
        transform: Scale { xScale: root.size / 24; yScale: root.size / 24 }

        ShapePath {
            fillColor: root._def.filled ? root.color : "transparent"
            strokeColor: root._def.filled ? "transparent" : root.color
            // -1, not a transparent stroke: the curve renderer still builds
            // geometry for a transparent one and loses the fill.
            strokeWidth: root._def.filled ? -1 : root.strokeWidth * 24 / Math.max(1, root.size)
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root._def.d }
        }
    }
}
