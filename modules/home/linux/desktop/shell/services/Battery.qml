pragma Singleton
import Quickshell
import Quickshell.Services.UPower
import "../config"

// Aggregate system battery (UPower's display device), reactive. `available` is false on
// desktops or anywhere there's no laptop battery, so the bar knows to hide the indicator.
Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool available: device ? device.isLaptopBattery : false
    // Quickshell hands you percentage on a 0..1 scale (checked it: 0.80 == 80%), so times 100.
    readonly property int percentage: device ? Math.round(device.percentage * 100) : 0
    // Use the real charge-state enum. "On AC" (!onBattery) is NOT the same as actually
    // charging: a plugged-in laptop holding at 80% reports PendingCharge, not Charging.
    readonly property bool charging: device ? device.state === UPowerDeviceState.Charging : false
    readonly property bool discharging: device ? device.state === UPowerDeviceState.Discharging : false
    readonly property bool low: available && discharging && percentage <= Config.batteryLowThreshold
}
