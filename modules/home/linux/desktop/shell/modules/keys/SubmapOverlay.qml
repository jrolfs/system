import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../theme"
import "../../services"

// While a Hyprland submap is active (the "window" mode), its binds float at the bottom
// centre of the focused monitor. The submap needs every keypress, so this never takes
// keyboard focus and lets the pointer through. It goes the instant the submap resets: by
// then the keys it lists have stopped meaning anything.
PanelWindow {
    id: overlay

    readonly property bool active: Keybinds.submap !== "" && card.sections.length > 0

    // Picked when the submap starts, so a focus change inside it doesn't remap the surface.
    property var targetScreen: null
    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name ?? "";
        const all = Quickshell.screens;
        for (let i = 0; i < all.length; i++)
            if (all[i].name === name) return all[i];
        return all.length > 0 ? all[0] : null;
    }
    onActiveChanged: {
        if (!active) return;
        targetScreen = focusedScreen();
        enter.restart();
    }
    screen: targetScreen

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:keys-submap"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.bottom: true
    margins.bottom: 96
    color: "transparent"
    mask: Region {}

    // room around the card for its entrance scale
    readonly property int halo: 12
    implicitWidth: card.width + halo * 2
    implicitHeight: card.height + halo * 2
    visible: active && targetScreen !== null

    BackgroundEffect.blurRegion: (Theme.blur && active) ? blurShape : null
    readonly property Region blurShape: Region {
        item: card
        radius: card.radius
    }

    SubmapCard {
        id: card
        anchors.centerIn: parent
        submapName: Keybinds.submap
        transformOrigin: Item.Bottom
    }

    ParallelAnimation {
        id: enter
        NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
        NumberAnimation { target: card; property: "scale"; from: 0.94; to: 1; duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
    }
}
