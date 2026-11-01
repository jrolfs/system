import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../config"

// Native wallpaper renderer: one background-layer surface per monitor showing
// Config.wallpaper, with a crossfade when it changes. Two Image layers; the incoming
// image loads into whichever one's hidden, then we flip `showA` to fade it in. No
// external daemon, no swww, no hyprpaper.
PanelWindow {
    id: w

    required property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell:wallpaper"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    // Ignore exclusive zones so the wallpaper covers the WHOLE screen, even behind the
    // island's reserved strip. Otherwise it gets shoved down and you're left with a band.
    exclusionMode: ExclusionMode.Ignore
    color: Theme.background // fallback color before/behind the images

    property bool showA: true
    readonly property string source: Config.wallpaper

    function toUrl(p) { return (p && p.length > 0) ? (p.startsWith("/") ? "file://" + p : p) : ""; }
    function apply(p) {
        const url = toUrl(p);
        if (url === "")
            return;
        const vis = showA ? imgA : imgB;
        const hid = showA ? imgB : imgA;
        if (vis.source.toString() === url)
            return;                                   // already on screen
        if (hid.source.toString() === url) {
            // The incoming image is already PARKED in the hidden layer, left there by an
            // earlier switch (go A -> B -> A and B's layer still holds A). Setting the same
            // source again is a no-op: no statusChanged, so the flip below never fired and
            // the wallpaper silently stayed on the old one until you switched twice more.
            // If it's decoded, flip now; if it's mid-load its own statusChanged flips it;
            // if it failed last time, kick a real reload.
            if (hid.status === Image.Ready) showA = !showA;
            else if (hid.status === Image.Error) { hid.source = ""; hid.source = url; }
            return;
        }
        // fresh image: load it into whichever layer is currently hidden, flip on Ready
        hid.source = url;
    }

    onSourceChanged: apply(source)
    Component.onCompleted: apply(source)

    Image {
        id: imgA
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize.width: w.screen ? w.screen.width : 0
        sourceSize.height: w.screen ? w.screen.height : 0
        opacity: w.showA ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.wallpaperFade; easing.type: Easing.InOutQuad } }
        onStatusChanged: if (status === Image.Ready && !w.showA) w.showA = true
    }

    Image {
        id: imgB
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize.width: w.screen ? w.screen.width : 0
        sourceSize.height: w.screen ? w.screen.height : 0
        opacity: w.showA ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Config.wallpaperFade; easing.type: Easing.InOutQuad } }
        onStatusChanged: if (status === Image.Ready && w.showA) w.showA = false
    }
}
