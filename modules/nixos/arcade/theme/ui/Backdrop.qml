import QtQuick 2.15
import QtGraphicalEffects 1.12
import "."

// Everything behind the panes: the desktop's wallpaper, or the focused game's
// art when it has some, veiled toward the palette so a bright screenshot
// doesn't outshine the menu. Also the blurred copy every Pane samples.
//
// The blur runs at a quarter of the screen's size and the panes scale it back
// up, which is both cheaper and softer than blurring at full size. It only
// re-renders when the art changes, so a still menu costs nothing.
Item {
    id: root

    // An image URL, or empty for the wallpaper alone.
    property string art: ""
    readonly property alias blurred: blurredTexture

    // Two layers, so one fades in over the other once its image has loaded.
    property bool showingA: false

    onArtChanged: {
        if (art === "") {
            artA.shown = false;
            artB.shown = false;
            return;
        }
        var incoming = showingA ? artB : artA;
        incoming.shown = false;
        incoming.source = art;
        showingA = !showingA;
        if (incoming.status === Image.Ready)
            reveal(incoming);
    }

    function reveal(layer) {
        artA.shown = layer === artA;
        artB.shown = layer === artB;
    }

    Item {
        id: content
        anchors.fill: parent

        Image {
            anchors.fill: parent
            source: "../assets/wallpaper.jpg"
            fillMode: Image.PreserveAspectCrop
            sourceSize.height: root.height
        }

        Image {
            id: artA
            property bool shown: false
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: shown ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: Theme.dSpring; easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
            }
            onStatusChanged: if (status === Image.Ready && root.showingA && root.art !== "") root.reveal(artA)
        }

        Image {
            id: artB
            property bool shown: false
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: shown ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: Theme.dSpring; easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
            }
            onStatusChanged: if (status === Image.Ready && !root.showingA && root.art !== "") root.reveal(artB)
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.bgDim
            opacity: artA.shown || artB.shown ? 0.55 : 0
            Behavior on opacity {
                NumberAnimation { duration: Theme.dSpring; easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
            }
        }
    }

    ShaderEffectSource {
        id: small
        sourceItem: content
        width: Math.max(1, Math.round(root.width / 4))
        height: Math.max(1, Math.round(root.height / 4))
        textureSize: Qt.size(width, height)
        smooth: true
        visible: false
    }

    FastBlur {
        id: blur
        width: small.width
        height: small.height
        source: small
        radius: Theme.station.blurRadius * Theme.unit / 4
        transparentBorder: false
    }

    ShaderEffectSource {
        id: blurredTexture
        sourceItem: blur
        hideSource: true
        smooth: true
        visible: false
    }
}
