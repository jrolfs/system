import QtQuick
import QtQuick.Effects
import Quickshell
import "../../theme"
import "../../services"
import "../../components"
import "../../config"

// The visual guts of the lock screen, split out of Lock.qml so it can be previewed
// without actually locking the session (you do NOT want to trigger a real lock just to
// eyeball it). Modelled on the macOS Tahoe lock: full-bleed wallpaper, a big translucent
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
    readonly property string userName: {
        const u = Quickshell.env("USER") || "user";
        return u.charAt(0) + u.slice(1);
    }

    SystemClock { id: clk; precision: SystemClock.Minutes }

    // ── blurred freeze-frame of the desktop + a scrim so text stays legible ──
    // The raw snapshot (hidden) is fed through a heavy MultiEffect blur; that frosted
    // result is what actually shows. Not the wallpaper: it's what was on screen the
    // instant before we locked (grabbed by LockState via grim). Dark fallback shows
    // underneath if the capture failed, so we never flash bare.
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
        blurMax: Config.lockBlur                  // big radius = proper frosted-glass blur
        autoPaddingEnabled: false
        // Driven off `shown`, exactly like the elements, so the background frosts IN on lock
        // and sharpens OUT on unlock with the identical animation + duration, just reversed.
        // Hidden value: 0.02 (a hair of blur, visually sharp) BEFORE unlock, to keep the blur
        // shader warm through the entrance beat so the frost-in doesn't hitch; but a true 0 on
        // unlock, so the last frame before teardown is pixel-identical to the live desktop and
        // there's no faintly-blurred frame lingering before it snaps back.
        blur: root.shown ? 1.0 : (LockState.unlocking ? 0.0 : 0.02)
        Behavior on blur { NumberAnimation { duration: Theme.dur(Theme.dExpand); easing.type: Easing.OutCubic } }
        // shown the instant it's ready (which, decoding sync above, is frame one), so
        // there's no black flash and no fade-from-black. Falls back to the dark rect
        // below only if the capture genuinely produced nothing.
        opacity: shot.status === Image.Ready ? 1 : 0
    }
    // darken a touch on top of the blur so the desktop's bright bits don't fight the text.
    // Fades in with the frost on lock and out with the unblur on unlock (same `shown` drive
    // as everything else), so the scrim never lingers as a dim frame at either end.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, Config.lockDim / 100)
        opacity: root.shown ? 1 : 0   // full 0 on unlock: no dim frame lingers before teardown; fades in on lock
        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dExpand); easing.type: Easing.OutCubic } }
    }
    Rectangle {
        anchors.fill: parent
        opacity: root.shown ? 1 : 0   // full 0 on unlock: no dim frame lingers before teardown; fades in on lock
        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dExpand); easing.type: Easing.OutCubic } }
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.28) }
            GradientStop { position: 0.28; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 0.72; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.35) }
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
                return;   // ignore lone modifiers
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
        WifiIcon {
            anchors.verticalCenter: parent.verticalCenter
            active: Network.connected
            strength: Network.connected ? (Network.isWifi ? Network.signalStrength : 1) : 0
            color: "#ffffff"
            dimColor: Qt.rgba(1, 1, 1, 0.35)
        }
    }

    // ── TOP: date over a big translucent clock ──
    Column {
        id: topCluster
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.height * 0.115
        spacing: -root.height * 0.01
        opacity: root.shown ? 1 : (LockState.unlocking ? 0 : 0.01)   // 0.01 (not 0) pre-warms its FBOs on entrance; true 0 on unlock leaves no ghost
        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dExpand); easing.type: Easing.OutCubic } }
        transform: Translate { y: root.shown ? 0 : -26; Behavior on y { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } } }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clk.date, "dddd, MMMM d")
            font.family: "SF Pro Display"
            font.weight: 600
            font.pixelSize: Math.round(root.height * 0.024)
            color: Qt.rgba(1, 1, 1, 0.82)
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0,0,0,0.35); shadowBlur: 0.5; shadowVerticalOffset: 1; blurMax: 16 }
        }
        Text {
            id: clockText
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clk.date, "h:mm")
            font.family: "SF Pro Display"
            font.pixelSize: Math.round(root.height * 0.135)
            font.letterSpacing: -7
            font.weight: 600
            color: Qt.rgba(1, 1, 1, 0.82)
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.28)
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
        anchors.bottomMargin: root.height * 0.085
        spacing: Math.round(root.height * 0.018)
        opacity: root.shown ? 1 : (LockState.unlocking ? 0 : 0.01)   // 0.01 (not 0) pre-warms its FBOs on entrance; true 0 on unlock leaves no ghost
        Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dExpand); easing.type: Easing.OutCubic } }
        transform: Translate { y: root.shown ? 0 : 26; Behavior on y { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } } }

        Rectangle {
            id: avatar
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(root.height * 0.055)
            height: width
            radius: width / 2
            color: Qt.rgba(1, 1, 1, 0.16)
            border.width: 1.5
            border.color: Qt.rgba(1, 1, 1, 0.45)
            scale: root.shown ? 1 : 0.88
            Behavior on scale { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
            Icon {
                anchors.centerIn: parent
                name: "person"
                size: parent.width * 0.62
                color: "#ffffff"
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.userName
            font.family: Theme.fontBody
            font.weight: 700
            font.letterSpacing: -0.5
            font.pixelSize: Math.round(root.height * 0.017)
            color: Qt.rgba(1, 1, 1, 0.95)
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0,0,0,0.3); shadowBlur: 0.5; shadowVerticalOffset: 1; blurMax: 12 }
        }

        // one slot, fixed height, so nothing jumps when the hint swaps for the pill
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(210, root.width * 0.09)
            height: Math.round(root.height * 0.029)

            // pre-reveal hint
            Text {
                anchors.centerIn: parent
                visible: opacity > 0
                opacity: root.typing ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                text: "Press Any Key to Enter Password"
                font.family: Theme.fontBody
                font.weight: 700
                font.letterSpacing: -0.5
                font.pixelSize: Math.round(root.height * 0.0135)
                color: Qt.rgba(1, 1, 1, 0.6)
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0,0,0,0.3); shadowBlur: 0.5; shadowVerticalOffset: 1; blurMax: 10 }
            }

            // password pill (frosted). Appears on the first keypress; shakes on a bad try.
            Rectangle {
                id: pill
                anchors.fill: parent
                radius: height / 2
                visible: opacity > 0
                opacity: root.typing ? 1 : 0
                scale: root.typing ? 1 : 0.96
                Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dEffects); easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier } }
                Behavior on scale { NumberAnimation { duration: Theme.dur(Theme.dSpring); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier } }
                color: pwField.activeFocus ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.15)
                border.width: 1
                property bool err: false
                border.color: err ? Qt.rgba(1, 0.35, 0.35, 0.9) : Qt.rgba(1, 1, 1, 0.3)
                Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                Behavior on border.color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                transform: Translate { id: shakeT; x: 0 }

                TextInput {
                    id: pwField
                    anchors.fill: parent
                    anchors.leftMargin: Theme.s4
                    anchors.rightMargin: Theme.s4
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignLeft
                    echoMode: TextInput.Password
                    passwordCharacter: ""
                    color: "#ffffff"
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.letterSpacing: 2
                    font.pixelSize: Math.round(root.height * 0.01)
                    clip: true
                    enabled: root.typing && LockState.prompting && !LockState.authenticating
                    onAccepted: { LockState.submit(text); text = ""; }

                    // Chunky, fully-rounded caret to match the macOS reference: a fat pill
                    // instead of the default hairline. Sized off root.height so it scales, and
                    // vertically centred in the field. Soft fade-blink rather than a hard toggle.
                    cursorDelegate: Rectangle {
                        id: caret
                        width: Math.max(3, Math.round(root.height * 0.0028))
                        radius: width / 2
                        height: Math.round(root.height * 0.017)
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(1, 1, 1, 0.75)
                        SequentialAnimation on opacity {
                            running: pwField.cursorVisible
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.15; duration: 580; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1.0;  duration: 580; easing.type: Easing.InOutQuad }
                            PauseAnimation { duration: 200 }
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Math.round(root.height * 0.001)   // clear the fat caret so it sits just left of the text, like the reference
                        anchors.verticalCenter: parent.verticalCenter
                        visible: pwField.text === ""
                        text: LockState.authenticating ? "Authenticating…" : "Enter Password"
                        font.family: Theme.fontBody
                        font.pixelSize: Math.round(root.height * 0.013)
                        font.weight: 700
                        font.letterSpacing: -0.5
                        color: Qt.rgba(1, 1, 1, 0.6)
                    }
                }
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
