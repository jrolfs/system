import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../config"
import "../../services"

// Rounded display corners: one overlay surface per monitor that paints the four little
// wedges the screen's corners would cut off if the panel were physically rounded. Purely
// cosmetic — the surface is click-THROUGH (empty input mask) and reserves no space, so it
// never steals a click or shoves a window around.
//
// Each corner is the same wedge shape rotated 0/90/180/270, so all four stay identical no
// matter the radius. Sits on the overlay layer so it rides above windows (including
// fullscreen ones) the way a real bezel would.
PanelWindow {
    id: sc

    required property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:screencorners"

    anchors { top: true; bottom: true; left: true; right: true }
    // cover the whole screen, and never reserve any of it
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // stays mapped through the whole animation; only drops out once the corners are gone,
    // otherwise unmapping the surface would cut the shrink off mid-way
    visible: r > 0.5

    // empty region = nothing on this surface accepts input, so clicks land on whatever's
    // underneath. Without this the overlay would swallow the whole screen.
    mask: Region {}

    // Game Mode squares everything off (window rounding goes to 0, the island flattens into
    // a bar), so the display corners square off with it — animated, so they retract into the
    // corners rather than blinking out, and grow back on the way out.
    readonly property int targetR: (Config.screenCorners && !GameMode.enabled) ? Config.screenCornerRadius : 0
    property real r: targetR
    Behavior on r { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }

    // one corner wedge: the area between the square corner and the arc that rounds it off.
    // SVG arc with sweep=0 curves AROUND the centre at (r,r), i.e. concave from the corner,
    // which leaves exactly the sliver that a rounded panel would hide.
    component Corner: Shape {
        id: cn
        property real size: 0
        width: size
        height: size
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        transformOrigin: Item.Center

        ShapePath {
            fillColor: "#000000"        // a bezel is physical: black on every scheme, light ones included
            strokeWidth: 0
            strokeColor: "transparent"
            PathSvg { path: `M 0,0 L ${cn.size},0 A ${cn.size},${cn.size} 0 0 0 0,${cn.size} Z` }
        }
    }

    Corner { size: sc.r; anchors.top: parent.top;    anchors.left: parent.left;   rotation: 0 }
    Corner { size: sc.r; anchors.top: parent.top;    anchors.right: parent.right; rotation: 90 }
    Corner { size: sc.r; anchors.bottom: parent.bottom; anchors.right: parent.right; rotation: 180 }
    Corner { size: sc.r; anchors.bottom: parent.bottom; anchors.left: parent.left;  rotation: 270 }
}
