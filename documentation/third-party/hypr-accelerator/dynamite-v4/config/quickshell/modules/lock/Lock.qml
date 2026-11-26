import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../config"
import "../../services"
import "../../components"

// Lock screen. WlSessionLock freezes all compositor input 'til you unlock, with one
// WlSessionLockSurface per monitor. All the state + PAM auth live in the LockState
// singleton ('cause the surface is its own isolated scope and can't reach ids). Fail
// closed: only LockState clears `locked`, and only on PamResult.Success. The look lives
// in LockContent (split out so it can be previewed without triggering a real lock).
WlSessionLock {
    id: lock
    locked: LockState.locked

    surface: WlSessionLockSurface {
        id: surf
        color: "black"   // behind LockContent's snapshot, so no flash of bare color

        LockContent {
            id: content
            anchors.fill: parent
            // which monitor this surface is on, so it can grab its own freeze-frame
            outputName: surf.screen ? surf.screen.name : ""
        }

        Component.onCompleted: content.grabFocus()
    }
}
