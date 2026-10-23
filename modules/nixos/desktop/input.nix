{ config, lib, ... }:

# Bluetooth, and the Apple Magic Keyboard and Trackpad that pair over it.

lib.mkIf config.desktop.enable {
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    # A keyboard that reconnects on its own after the machine wakes, without
    # a trip through the pairing UI, needs the controller to accept
    # reconnections from already-bonded devices while it isn't discoverable.
    settings.General.FastConnectable = true;
  };

  # Pairing UI. The bar's Bluetooth item opens it.
  services.blueman.enable = true;

  # hid_apple drives the Magic Keyboard. fnmode=1 puts media keys on the top
  # row and F1–F12 behind Fn, as on a Mac. The kernel's default, 3, only
  # picks that for keyboards it recognises as Apple's, and falls back to
  # F-keys first for anything else, so this pins it rather than trusting the
  # device table to know every model. ⌘ and ⌥ already arrive as Super and
  # Alt, which is what layout.kbd and the Hyprland bindings expect, so
  # nothing is swapped.
  boot.extraModprobeConfig = ''
    options hid_apple fnmode=1
  '';

  # The trackpad is a libinput device. Its gestures and scroll direction are
  # Hyprland settings (modules/home/linux/desktop/hyprland.nix), since Hyprland
  # reads libinput itself rather than through X.
  services.libinput.enable = true;
}
