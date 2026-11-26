{ config, lib, ... }:

# The Bluetooth adapter, for any host that turns on hardware.bluetooth. Kept
# apart from the desktop because a paired keyboard and trackpad are how Irulan
# is driven at the text console too, and the arcade's controllers need the same
# adapter whether or not Hyprland is running.
#
# Pairing needs an agent, and the only one the desktop provides is blueman's
# applet inside a Hyprland session. Without one bluetoothd reports the adapter
# as not pairable and turns pairing requests away. `bluetoothctl` registers its
# own agent for as long as it runs, so pair from it, at the console or over
# SSH. A bonded device reconnects with no agent at all.
#
# Apple's Magic Keyboard and Trackpad switch to USB HID while they're on a
# cable, and Linux can't pair them over USB the way a Mac does, so they pair
# over the air only. Each one remembers a single host. If it was ever paired to
# a Mac, it keeps trying that Mac and never advertises. Plug it into a Mac,
# unplug it, choose Forget This Device there, and it advertises again.

lib.mkIf config.hardware.bluetooth.enable {
  hardware.bluetooth = {
    powerOnBoot = true;
    settings.General = {
      # Battery levels over Bluetooth, which the DualSense and the Magic
      # devices report.
      Experimental = true;
      # A bonded device reconnects in a couple of seconds when it wakes, rather
      # than waiting for the next scan.
      FastConnectable = true;
    };
  };
}
