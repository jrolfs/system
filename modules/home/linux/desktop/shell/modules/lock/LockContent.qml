import QtQuick
import QtQuick.Effects
import Quickshell
import "../../theme"
import "../../services"
import "../../components"
import "../../config"

// The visual guts of the lock screen, split out of Lock.qml so it can be previewed
// without actually locking the session (you do NOT want to trigger a real lock just to
// eyeball it). Modelled on the macOS Tahoe lock: the frozen desktop, frosted, a big
// clock with the date above it up top, and an avatar / name down the bottom. The password
// box is HIDDEN until you press a key (before that it's a small "Press Any Key to Enter
// Password" hint, same as macOS). Auth still runs entirely through LockState (fail-closed,
// PAM); this is only chrome. Fills its parent (a WlSessionLockSurface, or a preview window).
Item {
    id: root

    // Drives both animations off one bool. `entered` flips true a beat AFTER the surface
    // is up (entrance); `shown` then also drops back to false the moment LockState starts
    // unlocking, so every element that animated IN on `shown` animates back OUT on the
    // way to teardown, using the exact same Behaviors. Symmetric lock / unlock for free.
    //
    // Why the beat: the entrance used to stutter and the exit didn't, purely because the
    // exit runs warm (every element's drop-shadow layer FBO + shader already built) while
    // the entrance ran cold. Two things make them match now:
    //   1. this timer lets the heavy first frame (snapshot decode + blur FBO build) settle
    //      before the spring-in starts, and
    //   2. the clusters sit at a hair above 0 opacity (not a hard 0) until `shown`, so Qt
    //      doesn't cull them and actually PAINTS them invisibly during this beat, building
    //      their shadow FBOs ahead of time. Then the spring-in runs fully warm, same as the
    //      exit. (A hard 0 gets culled, so the FBOs would build cold mid-animation instead.)
    property bool entered: false
    Component.onCompleted: enterDelay.start()
    Timer {
        id: enterDelay
        interval: Theme.reducedMotion ? 0 : 90
        repeat: false
        onTriggered: root.entered = true
    }
    readonly property bool shown: entered && !LockState.unlocking

    // flips true on the first keypress: swaps the hint out for the password field
    property bool typing: false

    // connector name of the monitor this surface is on (set by Lock.qml), used to pull
    // this screen's own freeze-frame out of LockState
    property string outputName: ""
    readonly property string shotUrl: LockState.shotFor(root.outputName)
    readonly property string userName: Quickshell.env("USER") || "user"

    // the lock's ink: the palette's cream, never pure white, so it sits with the rest of
    // the shell over any wallpaper
    readonly property color ink: Theme.foreground
    readonly property color shade: Theme.background
    // everything is sized off the surface height, so a 4K TV at scale 2 and a laptop panel
    // get the same composition
    readonly property real u: root.height

    SystemClock { id: clk; precision: SystemClock.Minutes }

    // ── blurred freeze-frame of the desktop + a scrim so text stays legible ──
    // The raw snapshot (hidden) is fed through a heavy MultiEffect blur; that frosted
    // result is what actually shows. Not the wallpaper: it's what was on screen the
    // instant before we locked (grabbed by LockState via grim). The palette's darkest
    // background shows underneath if the capture failed, so we never flash bare.
    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }
    Image {
        id: shot
        anchors.fill: parent
        source: root.shotUrl
        fillMode: Image.PreserveAspectCrop
        cache: false                 // path is reused each lock; don't serve a stale frame
        asynchronous: false          // file's already on disk; decode NOW so the first
                                     // painted frame IS the blur, not black then a fade
        visible: false               // sampled by the MultiEffect below, never drawn raw
    }
    MultiEffect {
        anchors.fill: parent
        source: shot
        blurEnabled: true
        blurMax: Config.lockBlur
        autoPaddingEnabled: false
        // Driven off `shown`, exactly like the elements, so the background frosts IN on lock
        // and sharpens OUT on unlock with the identical animation + duration, just reversed.
        // Hidden value: 0.02 (a hair of blur, visually sharp) BEFORE unlock, to keep the blur
        // shader warm through the entrance beat so the frost-in doesn't hitch; but a true 0 on
        // unlock, so the last frame before teardown is pixel-identical to the live desktop and
        // there's no faintly-blurred frame lingering before it snaps back.
        blur: root.shown ? 1.0 : (LockState.unlocking ? 0.0 : 0.02)
        Behavior on blur { NumberAnimation { duration: Theme.dur(Theme.dExpand); easing.type: Easing.OutCubic } }
        opacity: shot.status === Image.Ready ? 1 : 0
    }
    // A warm dim over the blur, the palette's darkest background rather than black, so the
    // frost reads as Gruvbox glass. Fades with the frost at both ends so no dim frame
    // lingers before teardown.
    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(root.shade, Config.lockDim / 100)
        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dExpand); easing.type: Easing.OutCubic } }
    }
    Rectangle {
        anchors.fill: parent
        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dExpand); easing.type: Easing.OutCubic } }
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.alpha(root.shade, 0.32) }
            GradientStop { position: 0.28; color: Theme.alpha(root.shade, 0.0) }
            GradientStop { position: 0.72; color: Theme.alpha(root.shade, 0.0) }
            GradientStop { position: 1.0; color: Theme.alpha(root.shade, 0.40) }
        }
    }

    // catches the first keypress (any key) to reveal the password field, seeding the
    // typed character. Holds focus until then; afterwards the TextInput owns focus.
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: !root.typing
        Keys.onPressed: (event) => {
            if (root.typing) return;
            switch (event.key) {
            case Qt.Key_Shift: case Qt.Key_Control: case Qt.Key_Alt:
            case Qt.Key_Meta: case Qt.Key_CapsLock: case Qt.Key_AltGr:
            case Qt.Key_Escape:
                return;   // ignore lone modifiers, and Esc means "not now"
            }
            root.typing = true;
            pwField.forceActiveFocus();
            if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 0x20) {
                pwField.text = event.text;
                pwField.cursorPosition = pwField.text.length;
            }
            event.accepted = true;
        }
    }

    // a click anywhere also brings the field up: on a TV the trackpad is often nearer
    // than the keyboard
    MouseArea {
        anchors.fill: parent
        enabled: !root.typing
        onClicked: { root.typing = true; pwField.forceActiveFocus(); }
    }

    // ── status glyphs, top-right ──
    Row {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: Theme.s5
        anchors.topMargin: Theme.s4
        spacing: Theme.s3
        opacity: root.shown ? 0.9 : (LockState.unlocking ? 0 : 0.01)   // 0.01 (not 0) pre-warms its FBOs on entrance; true 0 on unlock leaves no ghost
        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dExpand); easing.type: Easing.OutCubic } }

        BatteryIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: Battery.available
            level: Battery.percentage / 100
            low: Battery.low
            charging: Battery.charging
        }
        // Wi-Fi only: on a wired machine a full fan would claim a radio it doesn't have
        WifiIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: Network.isWifi || Network.wifiAvailable
            active: Network.connected
            strength: Network.isWifi ? Network.signalStrength : 0
            color: root.ink
            dimColor: Theme.alpha(root.ink, 0.35)
        }
    }

    // ── TOP: date over a big clock ──
    Column {
        id: topCluster
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.u * 0.115
        spacing: -root.u * 0.01
        opacity: root.shown ? 1 : (LockState.unlocking ? 0 : 0.01)   // 0.01 (not 0) pre-warms its FBOs on entrance; true 0 on unlock leaves no ghost
        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dExpand); easing.type: Easing.OutCubic } }
        transform: Translate { y: root.shown ? 0 : -26; Behavior on y { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } } }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clk.date, "dddd, MMMM d")
            font.family: Config.fontDisplay
            font.weight: Theme.wSemiBold
            font.pixelSize: Math.round(root.u * 0.024)
            color: Theme.alpha(root.ink, 0.86)
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Theme.alpha(root.shade, 0.45); shadowBlur: 0.5; shadowVerticalOffset: 1; blurMax: 16 }
        }
        Text {
            id: clockText
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clk.date, Config.clock24h ? "HH:mm" : "h:mm")
            font.family: Config.fontDisplay
            font.pixelSize: Math.round(root.u * 0.135)
            // display faces want tightening at this size; proportional, so it holds
            // whatever the face and the surface height
            font.letterSpacing: -Math.round(root.u * 0.135) * 0.035
            font.weight: Theme.wSemiBold
            font.features: { "tnum": 1 }   // the minute turning over must not shift the hour
            color: Theme.alpha(root.ink, 0.86)
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Theme.alpha(root.shade, 0.38)
                shadowBlur: 0.9
                shadowVerticalOffset: 2
                blurMax: 40
            }
        }
    }

    // ── BOTTOM: avatar, name, then the hint OR the password pill ──
    Column {
        id: bottomCluster
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.u * 0.085
        spacing: Math.round(root.u * 0.018)
        opacity: root.shown ? 1 : (LockState.unlocking ? 0 : 0.01)   // 0.01 (not 0) pre-warms its FBOs on entrance; true 0 on unlock leaves no ghost
        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dExpand); easing.type: Easing.OutCubic } }
        transform: Translate { y: root.shown ? 0 : 26; Behavior on y { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } } }

        Item {
            id: avatar
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(root.u * 0.062)
            height: width
            scale: root.shown ? 1 : 0.88
            Behavior on scale { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }

            // AccountsService's icon first (what a display manager shows), then ~/.face,
            // then the drawn glyph. Each step only on the previous one actually failing.
            readonly property var sources: [
                "file:///var/lib/AccountsService/icons/" + root.userName,
                "file://" + (Quickshell.env("HOME") || "") + "/.face"
            ]
            property int attempt: 0
            readonly property bool hasPhoto: face.status === Image.Ready

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Theme.glass
                visible: !avatar.hasPhoto
                Icon { anchors.centerIn: parent; name: "person"; size: parent.width * 0.6; color: root.ink }
            }
            Image {
                id: face
                anchors.fill: parent
                source: avatar.attempt < avatar.sources.length ? avatar.sources[avatar.attempt] : ""
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                cache: false
                visible: false
                layer.enabled: true
                onStatusChanged: if (status === Image.Error) avatar.attempt++
            }
            Rectangle { id: faceMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
            MultiEffect {
                anchors.fill: parent
                source: face
                maskSource: faceMask
                maskEnabled: true
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                visible: avatar.hasPhoto
            }
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: 1.5
                border.color: Theme.alpha(root.ink, 0.30)
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.userName
            font.family: Theme.fontBody
            font.weight: Theme.wSemiBold
            font.letterSpacing: -0.3
            font.pixelSize: Math.round(root.u * 0.017)
            color: Theme.alpha(root.ink, 0.95)
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Theme.alpha(root.shade, 0.4); shadowBlur: 0.5; shadowVerticalOffset: 1; blurMax: 12 }
        }

        // one slot, fixed height, so nothing jumps when the hint swaps for the pill
        Item {
            id: slot
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(240, root.u * 0.2)
            height: Math.round(root.u * 0.034)

            // pre-reveal hint
            Text {
                anchors.centerIn: parent
                visible: opacity > 0
                opacity: root.typing ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                text: "Press Any Key to Enter Password"
                font.family: Theme.fontBody
                font.weight: Theme.wMedium
                font.pixelSize: Math.round(root.u * 0.0135)
                color: Theme.alpha(root.ink, 0.62)
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Theme.alpha(root.shade, 0.4); shadowBlur: 0.5; shadowVerticalOffset: 1; blurMax: 10 }
            }

            // The password pill: a glass pane like every other surface in the shell, with
            // the rim. Appears on the first keypress; shakes on a bad try.
            Rectangle {
                id: pill
                anchors.fill: parent
                radius: height / 2
                visible: opacity > 0
                opacity: root.typing ? 1 : 0
                scale: root.typing ? 1 : 0.96
                Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                Behavior on scale { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                color: pwField.activeFocus ? Theme.glassStrong : Theme.glass
                border.width: 1
                property bool err: false
                border.color: err ? Theme.alpha(Theme.bad, 0.9) : Theme.rim
                Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                Behavior on border.color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                transform: Translate { id: shakeT; x: 0 }

                TextInput {
                    id: pwField
                    anchors.fill: parent
                    anchors.leftMargin: Math.round(pill.height * 0.5)
                    anchors.rightMargin: Math.round(pill.height * 0.5)
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignLeft
                    echoMode: TextInput.Password
                    // Dots by default so a keystroke visibly lands; an empty password
                    // character hides even the length, for whoever wants that.
                    passwordCharacter: Config.lockShowDots ? "•" : ""
                    passwordMaskDelay: 0
                    color: root.ink
                    font.family: Theme.fontBody
                    font.letterSpacing: Math.round(root.u * 0.0025)
                    font.pixelSize: Math.round(root.u * 0.016)
                    clip: true
                    enabled: root.typing && LockState.prompting && !LockState.authenticating
                    // Disabling drops focus, so each retry has to take it back or the next
                    // keystrokes go nowhere.
                    onEnabledChanged: if (enabled && root.typing) forceActiveFocus()
                    onAccepted: if (LockState.submit(text)) text = ""
                    Keys.onEscapePressed: {
                        if (text !== "") { text = ""; return; }
                        root.typing = false;
                        keyCatcher.forceActiveFocus();
                    }

                    // Chunky, fully-rounded caret to match the macOS reference: a fat pill
                    // instead of the default hairline, sized off the surface so it scales.
                    // Soft fade-blink rather than a hard toggle, at the configured rate.
                    cursorDelegate: Rectangle {
                        id: caret
                        width: Math.max(3, Math.round(root.u * 0.0028))
                        radius: width / 2
                        height: Math.round(root.u * 0.018)
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        color: Theme.alpha(Theme.accent, 0.9)
                        SequentialAnimation on opacity {
                            running: pwField.cursorVisible && Config.caretBlink > 0
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.15; duration: Config.caretBlink; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1.0;  duration: Config.caretBlink; easing.type: Easing.InOutQuad }
                            PauseAnimation { duration: Math.round(Config.caretBlink / 3) }
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Math.round(root.u * 0.006)   // clear the fat caret
                        anchors.verticalCenter: parent.verticalCenter
                        visible: pwField.text === ""
                        text: LockState.authenticating ? "Checking…" : "Enter Password"
                        font.family: Theme.fontBody
                        font.pixelSize: Math.round(root.u * 0.013)
                        font.weight: Theme.wMedium
                        color: Theme.alpha(root.ink, 0.5)
                    }
                }
            }
        }

        // What PAM said: a rejection, or its own note (faillock counting down, say). In a
        // fixed slot: an empty Text has no width, the Column skips it, and the whole
        // cluster would jump each time a message came and went.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: slot.width
            height: Math.round(root.u * 0.02)
            Text {
                anchors.centerIn: parent
                opacity: text !== "" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                text: LockState.errorMsg !== "" ? LockState.errorMsg
                    : (LockState.messageIsError ? LockState.message : "")
                font.family: Theme.fontBody
                font.weight: Theme.wMedium
                font.pixelSize: Math.round(root.u * 0.012)
                color: LockState.errorMsg !== "" || LockState.messageIsError ? Theme.bad : Theme.alpha(root.ink, 0.6)
            }
        }
    }

    // wrong-password feedback: shake the pill, flash its border, clear the field
    Connections {
        target: LockState
        function onErrorMsgChanged() {
            if (LockState.errorMsg !== "") {
                pwField.text = "";
                pill.err = true;
                shake.restart();
                errClear.restart();
            }
        }
    }
    SequentialAnimation {
        id: shake
        NumberAnimation { target: shakeT; property: "x"; to: -10; duration: 45 }
        NumberAnimation { target: shakeT; property: "x"; to: 9;  duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: -6; duration: 55 }
        NumberAnimation { target: shakeT; property: "x"; to: 3;  duration: 50 }
        NumberAnimation { target: shakeT; property: "x"; to: 0;  duration: 45 }
    }
    Timer { id: errClear; interval: 1200; onTriggered: pill.err = false }

    // focus the key-catcher so the very first keystroke reveals the field
    function grabFocus() { keyCatcher.forceActiveFocus(); }
}
