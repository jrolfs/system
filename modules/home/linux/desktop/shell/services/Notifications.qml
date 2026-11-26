pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../config"

// Notification server. Everything that lands gets kept (tracked) as history; a
// separate `poppedIds` set is just which ones are up right now as transient popups.
// Hiding a popup (timeout or close) does NOT drop it from history, only dismiss()
// does that. The popup stack renders `popups`, the control center renders `list`.
Singleton {
    id: root

    function asArray(m) { return !m ? [] : (m.values !== undefined ? m.values : m); }

    // Whole history, newest first.
    readonly property var list: asArray(server.trackedNotifications).slice().reverse()

    // Ids that are up as popups right now.
    property var poppedIds: []
    readonly property var popups: GlobalState.dnd ? [] : list.filter(n => poppedIds.indexOf(n.id) >= 0)

    // Whichever popup's up in the island right now (newest first). Auto-dismisses
    // after a beat (longer for Critical), and the countdown pauses while yer hovering
    // the island, so it don't vanish mid-read.
    readonly property var showing: popups.length > 0 ? popups[0] : null
    property bool popupHovered: false
    onShowingChanged: { if (showing && !popupHovered) dismissTimer.restart(); else if (!showing) dismissTimer.stop(); }
    onPopupHoveredChanged: { if (popupHovered) dismissTimer.stop(); else if (showing) dismissTimer.restart(); }
    Timer {
        id: dismissTimer
        interval: (root.showing && root.showing.urgency === NotificationUrgency.Critical) ? Config.notifTimeoutCritical : Config.notifTimeout
        onTriggered: if (root.showing) root.hidePopup(root.showing)
    }

    // Hide the transient popup but leave the notification sitting in history.
    function hidePopup(notif) {
        if (notif)
            poppedIds = poppedIds.filter(id => id !== notif.id);
    }

    // Yank it clean out of history.
    function dismiss(notif) {
        if (notif)
            notif.dismiss();
    }

    function clearAll() {
        for (const n of asArray(server.trackedNotifications).slice())
            n.dismiss();
        poppedIds = [];
    }

    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true;
            root.poppedIds = root.poppedIds.concat([notif.id]);
        }
    }
}
