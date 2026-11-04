import QtQuick 2.15
import QtGraphicalEffects 1.12
import "."

// A game's image fitted inside this item, keeping its shape, with rounded
// corners and the soft shadow floating surfaces get. Sized to the picture
// rather than the box, so the corners land on the art and not on letterboxing.
Item {
    id: root

    property string source: ""
    property real radius: Theme.rMd
    property bool shadow: true
    readonly property bool ready: image.status === Image.Ready

    readonly property real ratio: image.implicitHeight > 0 ? image.implicitWidth / image.implicitHeight : 1
    readonly property real fittedWidth: Math.min(width, height * ratio)
    readonly property real fittedHeight: Math.min(height, width / ratio)

    Image {
        id: image
        visible: false
        source: root.source
        asynchronous: true
        smooth: true
        mipmap: true
        width: root.fittedWidth
        height: root.fittedHeight
        sourceSize.height: Math.max(1, root.height * 1.5)
    }

    Rectangle {
        id: mask
        visible: false
        width: root.fittedWidth
        height: root.fittedHeight
        radius: root.radius
        antialiasing: true
    }

    Item {
        id: framed
        anchors.centerIn: parent
        width: root.fittedWidth
        height: root.fittedHeight
        opacity: root.ready ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.dEffects; easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
        }

        DropShadow {
            visible: root.shadow
            anchors.fill: rounded
            source: rounded
            radius: Theme.px(24)
            samples: 33
            verticalOffset: Theme.shadowY
            color: Qt.rgba(0, 0, 0, 0.35)
            cached: true
        }

        OpacityMask {
            id: rounded
            anchors.fill: parent
            source: image
            maskSource: mask
            cached: true
        }
    }
}
