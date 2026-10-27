pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

// Logging in through greetd: one user, one session, and the password as the
// only answer PAM is expected to ask for.
Singleton {
    id: root

    // GREETER_PREVIEW=1 runs the greeter inside an ordinary session to look at
    // it. greetd is never contacted and the power buttons only log. Every
    // password is wrong except "launch", which plays the exit and quits.
    readonly property bool preview: Quickshell.env("GREETER_PREVIEW") === "1"

    property bool busy: false
    property string error: ""
    // The session has been accepted and the greeter is fading out.
    property bool leaving: false

    signal failed()

    property string _password: ""
    property bool _answered: false

    function submit(password: string): void {
        if (busy || leaving)
            return;
        error = "";
        busy = true;
        _password = password;
        _answered = false;

        if (preview) {
            previewReply.restart();
            return;
        }

        // A session left over from an attempt that never finished would make
        // createSession fail outright.
        if (Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
        Greetd.createSession(Settings.userName);
    }

    function powerAction(verb: string): void {
        if (preview) {
            console.log("preview: would run systemctl", verb);
            return;
        }
        Quickshell.execDetached([Settings.systemctl, verb]);
    }

    function _fail(message: string): void {
        // greetd can still refuse the session after the fade has begun.
        leaving = false;
        launchDelay.stop();
        busy = false;
        _password = "";
        error = _describe(message);
        failed();
    }

    // pam_unix's failures arrive as PAM's error names, which say nothing to a
    // person. Anything else PAM says is passed on as it is.
    function _describe(message: string): string {
        if (!message || /AUTH_ERR|authentication failure/i.test(message))
            return "Incorrect password";
        if (/MAXTRIES/i.test(message))
            return "Too many attempts. Wait a moment and try again.";
        return message;
    }

    function _leave(): void {
        leaving = true;
        launchDelay.restart();
    }

    Connections {
        target: Greetd

        function onAuthMessage(message, isError, responseRequired, echoResponse) {
            if (!responseRequired) {
                if (isError)
                    root.error = message;
                return;
            }
            if (!echoResponse && !root._answered) {
                root._answered = true;
                Greetd.respond(root._password);
                root._password = "";
                return;
            }
            // A question after the password, such as a second factor or an
            // expired password's new one, has no field here to answer it.
            Greetd.cancelSession();
            root._fail(message);
        }

        function onAuthFailure(message) {
            root._fail(message);
        }

        function onError(message) {
            root._fail(message);
        }

        function onReadyToLaunch() {
            root._leave();
        }

        // Only now is the session greetd's to start. The marker is how the
        // scripts around Quickshell tell this exit from a crash.
        function onLaunched() {
            markLaunched.running = true;
        }
    }

    // As long as the fade-out. greetd expects the greeter gone soon after it
    // is told the session, so the animation plays before launch(), not after.
    Timer {
        id: launchDelay
        interval: 420
        onTriggered: {
            if (root.preview)
                Qt.quit();
            else
                Greetd.launch(Settings.session, [], false);
        }
    }

    Timer {
        id: previewReply
        interval: 700
        onTriggered: {
            if (root._password === "launch") {
                root.busy = false;
                root._leave();
            } else {
                root._fail("");
            }
        }
    }

    Process {
        id: markLaunched
        command: [Settings.touch, Quickshell.env("GREETER_MARKER") ?? ""]
        onExited: Qt.quit()
    }
}
