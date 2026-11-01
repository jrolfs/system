import QtQuick
import Quickshell.Hyprland
import "../../services"

// Watches volume/brightness and pokes OsdState, always at the focused monitor.
// `primed` swallows the initial value-settling churn at startup, so the OSD don't
// flash in yer face the second the shell loads.
Item {
    id: mgr

    property bool primed: false

    function focusedName() {
        return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
    }

    Timer {
        interval: 1500
        running: true
        onTriggered: mgr.primed = true
    }

    Connections {
        target: Audio
        function onVolumeChanged() {
            if (mgr.primed) OsdState.showVolume(Math.round(Audio.volume * 100), Audio.muted, mgr.focusedName());
        }
        function onMutedChanged() {
            if (mgr.primed) OsdState.showVolume(Math.round(Audio.volume * 100), Audio.muted, mgr.focusedName());
        }
    }

    Connections {
        target: Brightness
        function onChanged(name, value) {
            if (mgr.primed) OsdState.showBrightness(value, mgr.focusedName());
        }
    }
}
