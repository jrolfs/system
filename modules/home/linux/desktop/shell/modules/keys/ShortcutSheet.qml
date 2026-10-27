import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../theme"
import "../../config"
import "../../services"

// Every described keybinding on one glass sheet, centred on the focused monitor over a
// dimmed desktop. Its own surface rather than an island morph, because it wants the whole
// screen. Keyboard focus is exclusive while it is open so typing lands in the search field;
// Esc, the shortcut again, or a click outside the pane closes it.
PanelWindow {
    id: sheet

    property var targetScreen: null
    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name ?? "";
        const all = Quickshell.screens;
        for (let i = 0; i < all.length; i++)
            if (all[i].name === name) return all[i];
        return all.length > 0 ? all[0] : null;
    }
    Connections {
        target: Keybinds
        function onSheetOpenChanged() {
            if (!Keybinds.sheetOpen) return;
            sheet.targetScreen = sheet.focusedScreen();
            // an open island panel would hold keyboard focus against this one
            GlobalState.keepOnly("keys");
        }
    }
    screen: targetScreen

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:keys"
    WlrLayershell.keyboardFocus: Keybinds.sheetOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: targetScreen !== null && (Keybinds.sheetOpen || pane.opacity > 0.01)
    // click-through while it fades out, so the desktop is usable the moment it closes
    mask: Region { item: Keybinds.sheetOpen ? backdrop : null }

    BackgroundEffect.blurRegion: (Theme.blur && Keybinds.sheetOpen) ? blurShape : null
    readonly property Region blurShape: Region {
        item: pane
        radius: pane.radius
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Theme.scrim
        opacity: Keybinds.sheetOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }

        MouseArea {
            anchors.fill: parent
            onClicked: Keybinds.closeSheet()
        }
    }

    ShortcutSheetPane {
        id: pane
        anchors.centerIn: parent
        active: Keybinds.sheetOpen
        columns: sheet.width >= 1500 ? 3 : sheet.width >= 1000 ? 2 : 1
        maxHeight: sheet.height - 160

        opacity: Keybinds.sheetOpen ? 1 : 0
        scale: Keybinds.sheetOpen ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
        Behavior on scale { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
    }
}
