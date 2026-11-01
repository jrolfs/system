{ config, lib, pkgs, ... }:

# Game controllers over Bluetooth, PlayStation first.
#
# The DualSense and DualShock 4 need no driver here: the kernel's
# hid-playstation handles both, including the light bar, rumble and the
# battery level. What they do need is for the active session's user to be able
# to open them. game-devices-udev-rules tags Sony, 8BitDo, Nintendo and other
# pads for logind's uaccess, so whoever's session is on screen (the arcade user
# at the station, Jamie on the desktop) gets them, hidraw included, which is
# how SDL and Steam reach the DualSense's extra features.
#
# RetroArch maps a pad by name from retroarch-joypad-autoconfig, which the
# wrapper in default.nix already points at, and Pegasus goes through SDL,
# whose controller database knows both Sony pads. So a paired controller
# works in both with no per-device configuration.

lib.mkIf config.arcade.enable {
  # Its settings, fast reconnection included, are modules/nixos/bluetooth.nix.
  hardware.bluetooth.enable = true;

  services.udev.packages = [ pkgs.game-devices-udev-rules ];

  # game-devices-udev-rules also covers uinput, which Steam Input and
  # input remappers use to present a virtual pad.
  hardware.uinput.enable = true;
}
