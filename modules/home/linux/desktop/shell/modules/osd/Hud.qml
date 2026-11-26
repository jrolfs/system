import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../theme"
import "../../config"
import "../../services"
import "../../components"

// The HUD toast: a glass capsule at the bottom centre of the focused monitor with an icon
// and a line of text, Raycast's "Copied to clipboard". It scales up and fades in, holds for
// Config.hudTimeout, and fades back out. Driven by OsdState.showHud(), or from outside with
// `quickshell -c shell ipc call hud show "<text>"`. Click-through: it only confirms.
PanelWindow {
    id: hud

    // Picked when a toast starts rather than bound live, so a focus change mid-toast does
    // not tear the surface down and remap it on another monitor.
    property var targetScreen: null
    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name ?? "";
        const all = Quickshell.screens;
        for (let i = 0; i < all.length; i++)
            if (all[i].name === name) return all[i];
        return all.length > 0 ? all[0] : null;
    }
    Connections {
        target: OsdState
        function onHudSerialChanged() {
            hud.targetScreen = hud.focusedScreen();
            if (capsule.opacity > 0.5) pop.restart();
        }
    }
    screen: targetScreen

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:hud"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.bottom: true
    margins.bottom: 64
    color: "transparent"
    mask: Region {}

    // room around the capsule for its entrance scale
    readonly property int halo: 8
    implicitWidth: capsule.width + halo * 2
    implicitHeight: capsule.height + halo * 2
    visible: targetScreen !== null && (OsdState.hudActive || capsule.opacity > 0.01)

    // Blur only while the toast is up: the region does not fade, so leaving it in place
    // through the fade-out would leave a blurred patch with no pane over it.
    BackgroundEffect.blurRegion: (Theme.blur && OsdState.hudActive) ? blurShape : null
    readonly property Region blurShape: Region {
        item: capsule
        radius: Math.round(capsule.height / 2)
    }

    HudCapsule {
        id: capsule
        anchors.centerIn: parent

        opacity: OsdState.hudActive ? 1 : 0
        scale: OsdState.hudActive ? 1 : 0.9
        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
        Behavior on scale { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }

        // a second toast while one is up nudges it rather than replaying the entrance
        SequentialAnimation {
            id: pop
            NumberAnimation { target: capsule; property: "scale"; to: 0.96; duration: Theme.dur(Theme.dFast); easing.type: Easing.OutQuad }
            NumberAnimation { target: capsule; property: "scale"; to: 1; duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
        }
    }
}
