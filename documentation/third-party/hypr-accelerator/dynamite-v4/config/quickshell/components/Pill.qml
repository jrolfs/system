import QtQuick
import "../theme"

// The notch / OSD shell: a solid flat pill, fully rounded, that springs (no overshoot)
// whenever its size changes. Content goes in as children.
Surface {
    id: root

    fill: Theme.surfacePanel
    radius: Theme.rPill
    hairline: true

    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
    }
    Behavior on implicitHeight {
        NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
    }
}
