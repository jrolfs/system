import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// One screen of the login screen: the wallpaper blurred and dimmed, the clock,
// and on the first screen a glass card with the avatar and the password field,
// over a row of power buttons. Built from the same pieces as the shell's lock
// screen (modules/home/linux/desktop/shell/modules/lock), at the same sizes.
PanelWindow {
    id: win

    required property var modelData
    screen: modelData

    // Other screens get the wallpaper and the clock. Only one may own the
    // keyboard, and a second password field would only be a question of which.
    readonly property bool primary: modelData === Quickshell.screens[0]

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "greeter"
    WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: Colors.bg_dim

    // Everything below is sized for a 1080-pixel-high screen, which is the TV
    // at scale 2, and scales from there.
    readonly property real u: height > 0 ? height / 1080 : 1

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // The step response of a damped spring, as a bezier spline Qt can ease
    // along: the shell's Theme.springCurve, at its default damping.
    function springCurve(zeta: real): var {
        const n = 8;
        const w = 6.5 / zeta;
        const wd = w * Math.sqrt(1 - zeta * zeta);
        const k = zeta * w / wd;
        const val = t => 1 - Math.exp(-zeta * w * t) * (Math.cos(wd * t) + k * Math.sin(wd * t));
        const slope = t => (w * w / wd) * Math.exp(-zeta * w * t) * Math.sin(wd * t);
        const h = 1 / n;
        const points = [];
        for (let i = 0; i < n; i++) {
            const last = i === n - 1;
            const t0 = i * h, t1 = last ? 1 : (i + 1) * h;
            const y0 = val(t0), y1 = last ? 1 : val(t1);
            const s0 = slope(t0), s1 = last ? 0 : slope(t1);
            points.push(t0 + h / 3, y0 + s0 * h / 3, t1 - h / 3, y1 - s1 * h / 3, t1, y1);
        }
        return points;
    }
    readonly property var spring: springCurve(0.78)

    // A beat after the first frame, so the blur and the shadows are built
    // before anything starts moving.
    property bool entered: false
    readonly property bool shown: entered && !Auth.leaving
    Timer {
        interval: 80
        running: true
        onTriggered: win.entered = true
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Image {
        id: wallpaper
        anchors.fill: parent
        source: Settings.wallpaper
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: win.width
        sourceSize.height: win.height
        asynchronous: false
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        blur: 1.0
        saturation: -0.1
        opacity: wallpaper.status === Image.Ready ? 1 : 0
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.3)
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.28) }
            GradientStop { position: 0.3; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.35) }
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: win.height * 0.1
        spacing: -10 * win.u

        opacity: win.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        transform: Translate {
            y: win.shown ? 0 : -24 * win.u
            Behavior on y { NumberAnimation { duration: 620; easing.type: Easing.Bezier; easing.bezierCurve: win.spring } }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.3)
            shadowBlur: 0.8
            shadowVerticalOffset: 2
            blurMax: 32
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "dddd, MMMM d")
            font.family: "Geist"
            font.weight: 600
            font.pixelSize: 26 * win.u
            color: win.alpha(Colors.fg1, 0.85)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "h:mm")
            font.family: "Geist"
            font.weight: 600
            font.pixelSize: 150 * win.u
            font.letterSpacing: -5 * win.u
            color: win.alpha(Colors.fg1, 0.9)
        }
    }

    Loader {
        anchors.fill: parent
        active: win.primary
        sourceComponent: login
    }

    // Covers the screen in the colour the session's own first frame is, so
    // the login fades into the desktop rather than cutting to it.
    Rectangle {
        anchors.fill: parent
        color: Colors.bg_dim
        opacity: Auth.leaving ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }
    }

    Component {
        id: login

        Item {
            id: root

            Component.onCompleted: field.forceActiveFocus()

            Rectangle {
                id: card
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 90 * win.u
                width: 380 * win.u
                height: cardContent.implicitHeight + 64 * win.u
                radius: 32 * win.u
                color: win.alpha(Colors.bg0, 0.72)
                border.width: 1
                border.color: win.alpha(Colors.fg1, 0.12)

                opacity: win.shown ? 1 : 0
                scale: win.shown ? 1 : 0.94
                Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 620; easing.type: Easing.Bezier; easing.bezierCurve: win.spring } }

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.35)
                    shadowBlur: 1.0
                    shadowVerticalOffset: 10 * win.u
                    blurMax: 48
                }

                Column {
                    id: cardContent
                    anchors.centerIn: parent
                    spacing: 0

                    ClippingRectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 104 * win.u
                        height: width
                        radius: width / 2
                        color: Colors.bg3

                        Text {
                            anchors.centerIn: parent
                            visible: avatar.status !== Image.Ready
                            text: Settings.displayName.charAt(0)
                            font.family: "Geist"
                            font.weight: 600
                            font.pixelSize: 44 * win.u
                            color: Colors.fg1
                        }

                        Image {
                            id: avatar
                            anchors.fill: parent
                            source: Settings.avatar
                            sourceSize.width: width
                            sourceSize.height: height
                            fillMode: Image.PreserveAspectCrop
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: win.alpha(Colors.fg1, 0.16)
                        }
                    }

                    Item { width: 1; height: 18 * win.u }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Settings.displayName
                        font.family: "Geist"
                        font.weight: 600
                        font.pixelSize: 24 * win.u
                        font.letterSpacing: -0.3 * win.u
                        color: Colors.fg1
                    }

                    Item { width: 1; height: 24 * win.u }

                    Rectangle {
                        id: capsule
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 300 * win.u
                        height: 46 * win.u
                        radius: height / 2

                        property bool failed: false

                        color: win.alpha(Colors.fg1, field.activeFocus ? 0.09 : 0.06)
                        border.width: 1
                        border.color: failed ? win.alpha(Colors.red, 0.8)
                                    : win.alpha(Colors.fg1, field.activeFocus ? 0.22 : 0.12)
                        Behavior on border.color { ColorAnimation { duration: 160 } }

                        transform: Translate { id: shakeOffset }

                        TextInput {
                            id: field
                            anchors.fill: parent
                            anchors.leftMargin: 20 * win.u
                            anchors.rightMargin: 50 * win.u
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            passwordCharacter: "●"
                            passwordMaskDelay: 0
                            font.family: "Geist"
                            font.pixelSize: 14 * win.u
                            font.letterSpacing: 3 * win.u
                            color: Colors.fg1
                            selectionColor: win.alpha(Colors.yellow, 0.35)
                            clip: true
                            readOnly: Auth.busy || Auth.leaving

                            onTextChanged: if (text !== "") capsule.failed = false
                            onAccepted: if (text !== "") Auth.submit(text)
                            Keys.onEscapePressed: {
                                text = "";
                                Auth.error = "";
                                capsule.failed = false;
                            }

                            cursorDelegate: Rectangle {
                                width: Math.max(2, 2.5 * win.u)
                                height: 20 * win.u
                                radius: width / 2
                                color: Colors.yellow
                                visible: field.activeFocus && !field.readOnly

                                SequentialAnimation on opacity {
                                    running: field.cursorVisible
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.2; duration: 560; easing.type: Easing.InOutQuad }
                                    NumberAnimation { to: 1.0; duration: 560; easing.type: Easing.InOutQuad }
                                    PauseAnimation { duration: 180 }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 6 * win.u
                                visible: field.text === ""
                                text: Auth.busy ? "Checking…" : "Password"
                                font.family: "Geist"
                                font.pixelSize: 15 * win.u
                                color: win.alpha(Colors.fg0, 0.45)
                            }
                        }

                        Rectangle {
                            id: submit
                            anchors.right: parent.right
                            anchors.rightMargin: 6 * win.u
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34 * win.u
                            height: width
                            radius: width / 2
                            color: Colors.yellow

                            readonly property bool ready: field.text !== "" || Auth.busy
                            opacity: ready ? (Auth.busy ? pulse.value : 1) : 0
                            scale: ready ? 1 : 0.7
                            Behavior on scale { NumberAnimation { duration: 360; easing.type: Easing.Bezier; easing.bezierCurve: win.spring } }

                            QtObject {
                                id: pulse
                                property real value: 1
                                property SequentialAnimation animation: SequentialAnimation {
                                    running: Auth.busy
                                    loops: Animation.Infinite
                                    NumberAnimation { target: pulse; property: "value"; to: 0.45; duration: 420; easing.type: Easing.InOutQuad }
                                    NumberAnimation { target: pulse; property: "value"; to: 1; duration: 420; easing.type: Easing.InOutQuad }
                                }
                            }

                            Icon {
                                anchors.centerIn: parent
                                name: "arrow"
                                size: 18 * win.u
                                strokeWidth: 2.2 * win.u
                                color: Colors.bg0
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: field.text !== ""
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Auth.submit(field.text)
                            }
                        }
                    }

                    Item {
                        width: 300 * win.u
                        height: 30 * win.u

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: Auth.error
                            opacity: Auth.error !== "" ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                            font.family: "Geist"
                            font.weight: 500
                            font.pixelSize: 14 * win.u
                            color: Colors.red
                        }
                    }
                }
            }

            Connections {
                target: Auth
                function onFailed() {
                    field.text = "";
                    capsule.failed = true;
                    shake.restart();
                    field.forceActiveFocus();
                }
            }

            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeOffset; property: "x"; to: -12 * win.u; duration: 45 }
                NumberAnimation { target: shakeOffset; property: "x"; to: 10 * win.u; duration: 60 }
                NumberAnimation { target: shakeOffset; property: "x"; to: -7 * win.u; duration: 55 }
                NumberAnimation { target: shakeOffset; property: "x"; to: 4 * win.u; duration: 50 }
                NumberAnimation { target: shakeOffset; property: "x"; to: 0; duration: 45 }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 48 * win.u
                spacing: 12 * win.u

                opacity: win.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }

                PowerButton {
                    u: win.u
                    icon: "suspend"
                    label: "Suspend"
                    confirm: "Suspend?"
                    onActivated: Auth.powerAction("suspend")
                }
                PowerButton {
                    u: win.u
                    icon: "restart"
                    label: "Restart"
                    confirm: "Restart?"
                    onActivated: Auth.powerAction("reboot")
                }
                PowerButton {
                    u: win.u
                    icon: "power"
                    label: "Power Off"
                    confirm: "Power Off?"
                    onActivated: Auth.powerAction("poweroff")
                }
            }
        }
    }
}
