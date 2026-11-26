import QtQuick
import Quickshell
import "../../theme"
import "../../services"
import "../../components"
import "../controlcenter"

// Polkit auth prompt shown INSIDE the bar island (it morphs into this, see Bar.qml), in the
// control center's language: a sheet header with a live disc, a hero card carrying the
// request, a sunken pill for the secret with the key in its own disc, chips for the verbs.
// Same security rules as the old standalone dialog, don't loosen any of 'em:
//  * shows the REAL action (message + action id) so an app can't fake a generic prompt;
//  * the island holds EXCLUSIVE keyboard focus while morphed (Bar sets that) so
//    keystrokes can't leak to whatever's behind it;
//  * submits ONLY through flow.submit(). polkitd decides, we never check the password;
//  * dismiss (Esc / click-outside / Cancel) cancels the request (fail closed).
Item {
    id: root

    property bool active: false
    implicitHeight: content.implicitHeight
    clip: true

    readonly property var flow: Polkit.flow
    readonly property bool waiting: !!flow && flow.isResponseRequired
    readonly property bool checking: !!flow && !flow.isResponseRequired && !flow.isCompleted
    readonly property string errorText: {
        const f = Polkit.flow;
        if (!f) return "";
        if ((f.supplementaryMessage || "") !== "" && f.supplementaryIsError) return f.supplementaryMessage;
        if (f.failed) return "That password was not accepted";
        return "";
    }
    readonly property string infoText: {
        const f = Polkit.flow;
        if (!f) return "";
        return ((f.supplementaryMessage || "") !== "" && !f.supplementaryIsError) ? f.supplementaryMessage : "";
    }

    function cancel() { if (Polkit.flow) Polkit.flow.cancelAuthenticationRequest(); }
    function submit() {
        if (Polkit.flow && Polkit.flow.isResponseRequired && pwField.text !== "") {
            Polkit.flow.submit(pwField.text);
            pwField.text = "";
        }
    }

    onActiveChanged: {
        if (active) {
            pwField.text = "";
            Qt.callLater(() => pwField.forceActiveFocus());
        }
    }

    // Wrong password? Clear it, shake the field once, refocus so they can have another go.
    Connections {
        target: Polkit.flow
        ignoreUnknownSignals: true
        function onAuthenticationFailed() {
            pwField.text = "";
            shake.restart();
            pwField.forceActiveFocus();
        }
    }

    Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.s3

        // ── header: the sheet header's row, a live disc where the back disc would be ──
        Item {
            width: parent.width
            height: 32
            CcSheetBits.Disc {
                id: headDisc
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                size: 32
                live: true
                Icon { anchors.centerIn: parent; name: "lock"; size: 16; color: Theme.onAccent }
            }
            StyledText {
                anchors.left: headDisc.right
                anchors.leftMargin: Theme.s3
                capCentreIn: parent
                variant: "header"
                text: "Authentication required"
                color: Theme.inkPrimary
            }
        }

        // ── hero: what is actually being asked, verbatim from polkit ──
        Rectangle {
            id: hero
            width: parent.width
            implicitHeight: heroCol.implicitHeight + Theme.s3 * 2
            radius: Theme.rLg
            color: Theme.surfaceBase
            border.width: 1
            border.color: Theme.rim
            Column {
                id: heroCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.s3
                spacing: 3
                StyledText {
                    width: parent.width
                    wrapMode: Text.Wrap
                    variant: "body"
                    font.weight: Theme.wMedium
                    text: root.flow ? (root.flow.message || "An application is requesting elevated privileges.") : ""
                    color: Theme.inkPrimary
                }
                StyledText {
                    width: parent.width
                    visible: root.flow && (root.flow.actionId || "") !== ""
                    elide: Text.ElideRight
                    variant: "caption"
                    text: root.flow ? root.flow.actionId : ""
                    color: Theme.inkDim
                }
            }
        }

        // ── eyebrow: the field's label, or the pulse while polkitd checks ──
        CcSheetBits.SectionLabel {
            text: root.checking ? "" : ((root.flow && root.flow.inputPrompt) ? root.flow.inputPrompt.replace(/:\s*$/, "") : "Password")
            busy: root.checking
            busyText: "Authenticating"
        }

        // ── the secret: a sunken pill with the key in its own disc (the sheets' Track form) ──
        Item {
            id: fieldWrap
            width: parent.width
            height: 44
            transform: Translate { id: shakeT; x: 0 }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeT; property: "x"; to: -7; duration: 45 }
                NumberAnimation { target: shakeT; property: "x"; to: 6; duration: 70 }
                NumberAnimation { target: shakeT; property: "x"; to: -3; duration: 60 }
                NumberAnimation { target: shakeT; property: "x"; to: 0; duration: Theme.dur(Theme.dFast); easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
            }
            Rectangle {
                id: field
                anchors.fill: parent
                radius: Theme.rPill
                color: Theme.sunken
                border.width: 1
                border.color: root.errorText !== "" ? Theme.bad : pwField.activeFocus ? Theme.alpha(Theme.hue("polkit"), 0.55) : Theme.rim
                Behavior on border.color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                opacity: root.waiting ? 1 : 0.55
                Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }

                CcSheetBits.Disc {
                    id: keyDisc
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    size: 32
                    live: pwField.text !== ""
                    Icon { anchors.centerIn: parent; name: "lock"; size: 15; color: keyDisc.live ? Theme.onAccent : Theme.inkDim }
                }
                TextInput {
                    id: pwField
                    anchors.left: keyDisc.right
                    anchors.leftMargin: Theme.s3
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.s4
                    anchors.verticalCenter: parent.verticalCenter
                    echoMode: (root.flow && root.flow.responseVisible) ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    color: Theme.inkPrimary
                    font.family: Theme.fontBody
                    font.pixelSize: Theme.fsBody
                    clip: true
                    enabled: root.waiting
                    onAccepted: root.submit()
                    Keys.onEscapePressed: root.cancel()
                    StyledText {
                        capCentreIn: parent
                        visible: pwField.text === "" && root.waiting
                        variant: "body"
                        text: "Enter your password"
                        color: Theme.inkFaint
                    }
                }
            }
        }

        // ── status: an error in red, or polkit's own note ──
        StyledText {
            width: parent.width
            wrapMode: Text.Wrap
            visible: text !== ""
            variant: "caption"
            text: root.errorText !== "" ? root.errorText : root.infoText
            color: root.errorText !== "" ? Theme.bad : Theme.inkDim
        }

        // ── verbs: a quiet chip and an accent one, the sheets' chip form at button height ──
        Item {
            width: parent.width
            height: 34
            Row {
                anchors.right: parent.right
                spacing: Theme.s2
                // each verb carries the key that does the same, Raycast's outlined keycap
                Rectangle {
                    width: cancelRow.implicitWidth + Theme.s4 * 2
                    height: 34
                    radius: 17
                    color: cancelMa.containsMouse ? Theme.selection : "transparent"
                    border.width: 1
                    border.color: Theme.rim
                    Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                    Row {
                        id: cancelRow
                        anchors.centerIn: parent
                        spacing: Theme.s2
                        StyledText { anchors.verticalCenter: parent.verticalCenter; variant: "label"; font.weight: Theme.wMedium; text: "Cancel"; color: Theme.inkPrimary }
                        Keycap { anchors.verticalCenter: parent.verticalCenter; text: "esc"; ink: Theme.inkDim; edge: Theme.hairline }
                    }
                    MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.cancel() }
                }
                Rectangle {
                    width: authRow.implicitWidth + Theme.s4 * 2
                    height: 34
                    radius: 17
                    color: Theme.hue("polkit")
                    opacity: root.waiting ? (authMa.containsMouse ? 0.9 : 1) : 0.45
                    Behavior on opacity { NumberAnimation { duration: Theme.dur(Theme.dFast) } }
                    Row {
                        id: authRow
                        anchors.centerIn: parent
                        spacing: Theme.s2
                        StyledText { anchors.verticalCenter: parent.verticalCenter; variant: "label"; font.weight: Theme.wMedium; text: "Authenticate"; color: Theme.onAccent }
                        Keycap { anchors.verticalCenter: parent.verticalCenter; text: "↵"; ink: Theme.onAccent; edge: Theme.alpha(Theme.onAccent, 0.35) }
                    }
                    MouseArea { id: authMa; anchors.fill: parent; hoverEnabled: true; enabled: root.waiting; cursorShape: Qt.PointingHandCursor; onClicked: root.submit() }
                }
            }
        }
    }

    component Keycap: Rectangle {
        property alias text: capLabel.text
        property color ink: Theme.inkDim
        property color edge: Theme.hairline
        width: Math.max(20, capLabel.implicitWidth + 10)
        height: 20
        radius: 6
        color: "transparent"
        border.width: 1
        border.color: edge
        StyledText { id: capLabel; anchors.centerIn: parent; variant: "caption"; color: parent.ink }
    }
}
