import QtQuick
import QtQuick.Shapes
import "../theme"

// Battery icon built from shapes, not a font glyph: an outline plus a terminal nub,
// the fill sized to the level, and the percentage sitting INSIDE the cell (iOS style).
// When CHARGING the fill goes green and a lightning bolt takes the place of the digits.
// The inner mark (digits or bolt) is a knockout so it stays readable at any level: a
// light copy (inkPrimary) shows over the empty part, and a dark copy (contrast of the
// fill) gets clipped to the fill width and shows over the filled part.
Item {
    id: root

    property real level: 0       // 0..1
    property bool low: false
    property bool charging: false

    implicitWidth: 30
    implicitHeight: 16

    readonly property real frac: Math.max(0, Math.min(1, level))
    readonly property int pct: Math.round(frac * 100)
    readonly property color fillColor: charging ? Theme.good : (low ? Theme.bad : Theme.accent)
    readonly property color onFillInk: Theme.lum(fillColor) > 0.55 ? "#0b0b0b" : "#f6f6f6"
    readonly property int numSize: Theme.fsCaption - 1

    // lightning bolt: the Material "flash" outline squeezed into a 5×10 box, flat fill
    component Bolt: Shape {
        id: boltRoot
        property color ink: "#ffffff"
        implicitWidth: 5
        implicitHeight: 10
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: boltRoot.ink
            strokeWidth: 0
            strokeColor: "transparent"
            startX: 0; startY: 0
            PathLine { x: 0;   y: 5.5 }
            PathLine { x: 1.5; y: 5.5 }
            PathLine { x: 1.5; y: 10 }
            PathLine { x: 5;   y: 4 }
            PathLine { x: 3;   y: 4 }
            PathLine { x: 5;   y: 0 }
            PathLine { x: 0;   y: 0 }
        }
    }

    Rectangle {
        id: body
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 3
        height: parent.height
        radius: 4.5
        color: "transparent"
        border.color: Theme.inkDim
        border.width: 1.5
        antialiasing: true

        // inner area, inset inside the border; clips the fill and the knockout mark
        Item {
            id: inner
            anchors.fill: parent
            anchors.margins: 2.5
            clip: true

            // light copy, the one that shows over the EMPTY region
            StyledText {
                anchors.centerIn: parent
                visible: !root.charging
                font.pixelSize: root.numSize
                font.weight: Theme.wSemiBold
                text: root.pct
                color: Theme.inkPrimary
            }
            Bolt {
                anchors.centerIn: parent
                visible: root.charging
                ink: Theme.inkPrimary
            }

            // the level fill itself (accent / green / red)
            Rectangle {
                id: fill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * root.frac
                radius: 2
                color: root.fillColor
                antialiasing: true
                Behavior on width { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
            }

            // dark copy, clipped to the fill width: the knockout that shows over the fill
            Item {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: fill.width
                clip: true
                Item {
                    id: holder
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: inner.width   // full inner width so kids centre on the CELL, not the clip
                    StyledText {
                        anchors.centerIn: parent
                        visible: !root.charging
                        font.pixelSize: root.numSize
                        font.weight: Theme.wSemiBold
                        text: root.pct
                        color: root.onFillInk
                    }
                    Bolt {
                        anchors.centerIn: parent
                        visible: root.charging
                        ink: root.onFillInk
                    }
                }
            }
        }
    }

    // terminal nub
    Rectangle {
        anchors.left: body.right
        anchors.leftMargin: 1
        anchors.verticalCenter: parent.verticalCenter
        width: 2.5
        height: parent.height * 0.4
        radius: 1.25
        color: Theme.inkDim
    }
}
