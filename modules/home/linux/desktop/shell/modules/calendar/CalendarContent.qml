import QtQuick
import Quickshell
import "../../theme"
import "../../config"
import "../../components"

// Calendar shown INSIDE the bar island: it morphs into this when you press the
// clock (see Bar.qml). Flat, compact month grid: today is the one accent mark, the
// other months dimmed (or hidden, Config.calendarShowAdjacent). ◀ / ▶ page through months (identical buttons); tapping the
// title (or the arrow keys) jumps back to today. Esc and click-outside dismiss (the
// bar handles that).
Item {
    id: root

    property bool active: false
    implicitHeight: col.implicitHeight
    clip: true

    SystemClock { id: sysclock; precision: SystemClock.Minutes }
    readonly property date today: sysclock.date

    // which month we're showing, as an offset from today's month (0 = this month)
    property int monthOffset: 0
    onActiveChanged: {
        if (active) Qt.callLater(() => keyCatcher.forceActiveFocus());
        else monthOffset = 0;   // always pop back open on the current month
    }

    readonly property date shown: new Date(root.today.getFullYear(), root.today.getMonth() + root.monthOffset, 1)
    readonly property int shownYear: root.shown.getFullYear()
    readonly property int shownMonth: root.shown.getMonth()    // 0-11
    readonly property var monthNames: ["January", "February", "March", "April", "May", "June",
                                       "July", "August", "September", "October", "November", "December"]

    function close() { GlobalState.calendarOpen = false; }

    readonly property int weekStart: Math.max(0, Math.min(6, Config.weekStartsOn | 0))   // 0 = Sunday
    // narrow weekday names in the locale's language, rotated to start on weekStart
    readonly property var weekdays: {
        const loc = Qt.locale();
        const out = [];
        for (let i = 0; i < 7; i++) out.push(loc.dayName((root.weekStart + i) % 7, Locale.NarrowFormat));
        return out;
    }

    // 42 cells (6 weeks, starting on weekStart): { day, inMonth, today }. Always six rows,
    // so paging between months never changes the island's height.
    readonly property var cells: {
        const y = root.shownYear, m = root.shownMonth;
        const startDow = (new Date(y, m, 1).getDay() - root.weekStart + 7) % 7;   // leading days from the previous month
        const daysInMonth = new Date(y, m + 1, 0).getDate();
        const daysInPrev = new Date(y, m, 0).getDate();
        const t = root.today;
        const curMonth = (t.getFullYear() === y && t.getMonth() === m);
        const out = [];
        for (let i = 0; i < 42; i++) {
            const dn = i - startDow + 1;
            let day, inMonth;
            if (dn < 1) { day = daysInPrev + dn; inMonth = false; }
            else if (dn > daysInMonth) { day = dn - daysInMonth; inMonth = false; }
            else { day = dn; inMonth = true; }
            out.push({ day: day, inMonth: inMonth, today: inMonth && curMonth && day === t.getDate() });
        }
        return out;
    }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.active
        Keys.onEscapePressed: root.close()
        Keys.onLeftPressed: root.monthOffset--
        Keys.onRightPressed: root.monthOffset++
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.s2

        // header: ◀ Month Year ▶
        Item {
            width: parent.width
            height: Config.calendarCellHeight

            // previous month. Identical to nextBtn below in look + behaviour (only the
            // anchor side, arrow direction, and offset step differ).
            Rectangle {
                id: prevBtn
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30; radius: 15
                color: prevMa.pressed ? Theme.hue("calendar") : prevMa.containsMouse ? Theme.selection : "transparent"
                border.width: 1
                border.color: Theme.rim
                Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                Icon { anchors.centerIn: parent; name: "back"; size: 14; color: prevMa.pressed ? Theme.onAccent : Theme.inkPrimary }
                MouseArea {
                    id: prevMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.monthOffset--
                }
            }

            Rectangle {
                id: titleBtn
                anchors.centerIn: parent
                width: titleText.implicitWidth + Theme.s3
                height: 28
                radius: Theme.rMd
                color: titleMa.containsMouse ? Theme.selection : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                StyledText {
                    id: titleText
                    anchors.centerIn: parent
                    variant: "label"
                    font.weight: Theme.wSemiBold
                    text: root.monthNames[root.shownMonth] + " " + root.shownYear
                    color: Theme.inkPrimary
                }
                MouseArea { id: titleMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.monthOffset = 0 }
            }

            // next month. Mirror of prevBtn.
            Rectangle {
                id: nextBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30; radius: 15
                color: nextMa.pressed ? Theme.hue("calendar") : nextMa.containsMouse ? Theme.selection : "transparent"
                border.width: 1
                border.color: Theme.rim
                Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                Icon { anchors.centerIn: parent; name: "back"; rotation: 180; size: 14; color: nextMa.pressed ? Theme.onAccent : Theme.inkPrimary }
                MouseArea {
                    id: nextMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.monthOffset++
                }
            }
        }

        // weekday header
        Row {
            width: parent.width
            Repeater {
                model: root.weekdays
                delegate: Item {
                    required property var modelData
                    width: col.width / 7
                    height: 18
                    StyledText {
                        anchors.centerIn: parent
                        variant: "caption"
                        text: modelData
                        color: Theme.inkDim
                    }
                }
            }
        }

        // day grid (6 weeks)
        Grid {
            width: parent.width
            columns: 7
            rowSpacing: 2
            Repeater {
                model: root.cells
                delegate: Item {
                    id: cell
                    required property var modelData
                    width: col.width / 7
                    height: Config.calendarCellHeight
                    readonly property bool shownDay: modelData.inMonth || Config.calendarShowAdjacent
                    Rectangle {
                        anchors.centerIn: parent
                        // a circle that fits the cell whichever way it was sized
                        width: Math.min(cell.width, cell.height) - 4
                        height: width
                        radius: width / 2
                        color: cell.modelData.today ? Theme.hue("calendar")
                             : dayMa.containsMouse && cell.shownDay ? Theme.selection : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.dur(Theme.dFast) } }
                        StyledText {
                            anchors.centerIn: parent
                            visible: cell.shownDay
                            variant: "caption"
                            font.weight: cell.modelData.today ? Theme.wSemiBold : Theme.wRegular
                            text: cell.modelData.day
                            color: cell.modelData.today ? Theme.onAccent
                                 : cell.modelData.inMonth ? Theme.inkPrimary : Theme.inkFaint
                        }
                    }
                    MouseArea { id: dayMa; anchors.fill: parent; hoverEnabled: true }
                }
            }
        }
    }
}
