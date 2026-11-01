pragma Singleton
import Quickshell

// Runtime UI state: which panels are open. Toggled by global shortcuts / IPC
// (Phase 1+). Not the same as Config: nothing here is a user preference, and it all
// resets on reload (stash it in Config/PersistentProperties if it has to survive).
Singleton {
    id: root

    property bool launcherOpen: false
    property bool controlCenterOpen: false
    property bool logoutOpen: false
    property bool wallpaperPickerOpen: false
    property bool settingsOpen: false
    // which Settings page to land on when it next opens ("" = wherever it was left). The
    // control center's "Edit in Settings" chip sets it so you arrive on the layout editor.
    property string settingsPage: ""
    property bool calendarOpen: false

    // Only ONE island panel open at a time. We enforce it here, not at the call sites, so
    // it holds no matter how a panel got opened: a toggle, an IPC open(), or one picker
    // handing off to another. Whenever one flips true, the rest get forced false. Setting
    // a bool that's already false is a no-op, so this never recurses on itself. (polkit
    // isn't a GlobalState panel; the bar already mutes everything else while an auth
    // prompt is up.) settings is DELIBERATELY excluded: it's its own floating window now,
    // not an island morph, so it coexists with the island. Clicking the island (which opens
    // one of these panels) must NOT close the settings window, and vice versa.
    function keepOnly(which) {
        if (which !== "launcher")  launcherOpen = false;
        if (which !== "cc")        controlCenterOpen = false;
        if (which !== "logout")    logoutOpen = false;
        if (which !== "wallpaper") wallpaperPickerOpen = false;
        if (which !== "calendar")  calendarOpen = false;
    }
    onLauncherOpenChanged:        if (launcherOpen)         keepOnly("launcher");
    onControlCenterOpenChanged:   if (controlCenterOpen)    keepOnly("cc");
    onLogoutOpenChanged:          if (logoutOpen)           keepOnly("logout");
    onWallpaperPickerOpenChanged: if (wallpaperPickerOpen)  keepOnly("wallpaper");
    onCalendarOpenChanged:        if (calendarOpen)         keepOnly("calendar");

    // Hold the island open without a pointer over it (qs ipc call island open|close|toggle).
    // A keyboard way to the open island, and the way to drive it for a capture.
    property bool islandHold: false
    function toggleIsland() { islandHold = !islandHold; }

    // Do Not Disturb: suppresses notification popups, though history still records them.
    property bool dnd: false
    function toggleDnd() { dnd = !dnd; }

    // Lock is a transient request (a signal, not stored state) so a config reload can't
    // flip some "locked" bool back to false and quietly drop the lock on you.
    signal lockRequested()
    function requestLock() { lockRequested(); }

    function toggleLauncher() { launcherOpen = !launcherOpen; }
    function toggleControlCenter() { controlCenterOpen = !controlCenterOpen; }
    function toggleLogout() { logoutOpen = !logoutOpen; }
    function toggleWallpaperPicker() { wallpaperPickerOpen = !wallpaperPickerOpen; }
    function toggleSettings() { settingsOpen = !settingsOpen; }
    function toggleCalendar() { calendarOpen = !calendarOpen; }
}
