import QtQuick 2.15
import "."

// The systems, as a row of capsules with the current one in an accent pill
// that springs from tab to tab, the way the shell's workspace capsules move.
// L1 and R1 sit at either end as the reminder of how to get across.
Item {
    id: root

    // [{ label }]
    property var tabs: []
    property int current: 0

    implicitHeight: Theme.px(40)

    Keycap {
        id: previous
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "L1"
        opacity: root.tabs.length > 1 ? 1 : 0
    }

    ListView {
        id: view
        anchors.left: previous.right
        anchors.leftMargin: Theme.s3
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(contentWidth, root.width - previous.width - next.width - 2 * Theme.s3)
        height: parent.height
        orientation: ListView.Horizontal
        interactive: false
        clip: true
        spacing: Theme.s1
        model: root.tabs.length
        currentIndex: root.current
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

        highlightFollowsCurrentItem: false
        highlight: Rectangle {
            x: view.currentItem ? view.currentItem.x : 0
            width: view.currentItem ? view.currentItem.width : 0
            height: view.height
            radius: height / 2
            color: Theme.accent
            antialiasing: true
            Behavior on x {
                NumberAnimation { duration: Theme.dSpring; easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
            }
            Behavior on width {
                NumberAnimation { duration: Theme.dSpring; easing.type: Easing.Bezier; easing.bezierCurve: Theme.springBezier }
            }
        }

        delegate: Item {
            readonly property bool selected: index === view.currentIndex

            width: label.implicitWidth + 2 * Theme.s4
            height: view.height

            Label {
                id: label
                anchors.centerIn: parent
                text: root.tabs[index] ? root.tabs[index].label : ""
                font.weight: Font.Medium
                color: parent.selected ? Theme.onAccent : Theme.inkDim
                Behavior on color {
                    ColorAnimation { duration: Theme.dEffects; easing.type: Easing.Bezier; easing.bezierCurve: Theme.effectsBezier }
                }
            }
        }
    }

    Keycap {
        id: next
        anchors.left: view.right
        anchors.leftMargin: Theme.s3
        anchors.verticalCenter: parent.verticalCenter
        text: "R1"
        opacity: root.tabs.length > 1 ? 1 : 0
    }
}
