pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import "../theme"
import "../config"

// Lock state + PAM auth, kept in a singleton 'cause the per-screen
// WlSessionLockSurface is its own isolated scope and can't see ids, only this.
// `locked` is cleared in exactly ONE place (unlockTimer), and that timer is armed
// from exactly ONE place (PamResult.Success). Every failure or error stays locked,
// no exceptions (fail closed). Password's never stored, logged, or echoed. Ever.
Singleton {
    id: root

    property bool locked: false
    property string errorMsg: ""
    property bool authenticating: false
    readonly property bool prompting: pam.responseRequired
    readonly property string message: pam.message
    readonly property bool messageIsError: pam.messageIsError

    // true for the brief window between a successful auth and the surface actually
    // tearing down, so LockContent can play its exit animation before we drop the lock.
    // Auth already succeeded here; this only defers the teardown, it never gates it.
    property bool unlocking: false

    // Per-output snapshot of the desktop, grabbed the instant before we lock, so the
    // lock screen can show a blurred freeze-frame of what was on screen (macOS-style)
    // instead of the wallpaper. Keyed by connector name -> file:// url. The lock surface
    // is opaque, so this MUST be captured before `locked` flips (can't blur through it).
    // No cache-buster needed: the surface (and its Image) is recreated on every lock and
    // the Image loads with cache: false, so it always reads the fresh file off disk.
    property var shots: ({})
    function shotFor(name) { return shots[name] ?? ""; }

    function lock() {
        if (locked)
            return;
        errorMsg = "";
        authenticating = false;
        unlocking = false;
        // Grab the screen(s), THEN lock. engageLock() runs on grim's exit, and a safety
        // timer engages it anyway if grim stalls or isn't installed (fail closed: a
        // missing screenshot must never mean a missing lock).
        captureThenLock();
    }

    // Actually engage the lock. Idempotent + guarded so the grim exit and the safety
    // timer can't double-fire it.
    function engageLock() {
        if (locked)
            return;
        safety.stop();
        unlocking = false;
        locked = true;
        startPam();
    }

    // A PAM conversation that will not start (no such service file, say) leaves the
    // screen locked with a message rather than a field that silently does nothing.
    function startPam() {
        if (!pam.start()) {
            errorMsg = "Authentication unavailable";
            retry.restart();
        }
    }

    function captureThenLock() {
        const dir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp";
        const map = {};
        const cmds = [];
        for (const s of Quickshell.screens) {
            const path = dir + "/qs-lockshot-" + s.name + ".jpg";
            map[s.name] = "file://" + path;
            // grim -o <output> writes just that monitor; run them in parallel then wait.
            // JPEG, not PNG: PNG's zlib encode of a full-res frame runs ~850ms (that's the
            // delay before the lock shows), JPEG is ~75ms. The heavy blur on top eats any
            // JPEG artifacts, so quality here is irrelevant. Fast is what matters.
            cmds.push("grim -t jpeg -q " + Config.lockShotQuality + " -o '" + s.name + "' '" + path + "'");
        }
        root.shots = map;
        safety.restart();                 // hard cap: lock within 700ms no matter what
        shotProc.command = ["sh", "-c", cmds.join(" & ") + " ; wait"];
        shotProc.running = true;
    }

    // grim done (or failed): the freeze-frames are on disk, engage the lock now.
    Process {
        id: shotProc
        onExited: root.engageLock()
    }

    // Fail-closed backstop: if grim wedges or is absent, lock anyway. The lock just
    // falls back to a dark background instead of the blurred snapshot.
    Timer {
        id: safety
        interval: 700
        repeat: false
        onTriggered: root.engageLock()
    }

    // false when the password was not taken (PAM not prompting yet, already checking, or
    // empty), so the field can keep what was typed instead of eating it
    function submit(pw) {
        if (!pam.responseRequired || authenticating || pw.length === 0)
            return false;
        errorMsg = "";
        authenticating = true;
        pam.respond(pw);
        return true;
    }

    PamContext {
        id: pam
        // Our own service, declared in Nix as security.pam.services.quickshell, so the
        // stack is plain pam_unix and nothing borrowed from login or su. On the machine
        // this shell came from, "login" (try_first_pass, nullok, faillock) ACCEPTED a
        // wrong password through Quickshell's conversation: it failed open. Re-test a
        // wrong password after touching anything PAM. Without the service file Quickshell
        // refuses to start the conversation at all ("not a file"), so a missing file fails
        // closed: still locked, with "Authentication unavailable" under the field.
        config: "quickshell"

        onCompleted: result => {
            root.authenticating = false;
            if (result === PamResult.Success) {
                // Don't drop the surface yet: flip `unlocking` so LockContent can play its
                // exit animation, then unlockTimer clears `locked` once it's done. This is
                // the ONLY path that arms unlockTimer, so it stays fail-closed.
                root.unlocking = true;
                unlockTimer.restart();
            } else {
                root.errorMsg = result === PamResult.MaxTries ? "Too many attempts"
                              : result === PamResult.Error ? "Authentication error"
                              : "Incorrect password";
                root.startPam(); // fresh prompt, still locked
            }
        }
        // An error ends the conversation without a result, so without a restart the field
        // stays disabled for good. Still locked either way.
        onError: {
            root.authenticating = false;
            root.errorMsg = "Authentication error";
            if (root.locked && !root.unlocking) retry.restart();
        }
    }
    // a beat before retrying, so a PAM stack that errors or refuses instantly cannot spin
    Timer {
        id: retry
        interval: 1000
        onTriggered: if (root.locked && !root.unlocking && !pam.active) root.startPam()
    }

    // Fires after the exit animation. The one and only place `locked` gets cleared, and
    // it's only ever armed by PamResult.Success above. Length matches LockContent's exit.
    Timer {
        id: unlockTimer
        interval: Theme.reducedMotion ? 0 : Theme.dExpand   // matches LockContent's exit
        repeat: false
        onTriggered: {
            root.locked = false;
            root.unlocking = false;
        }
    }
}
