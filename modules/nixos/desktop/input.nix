{ config, lib, ... }:

# The desktop's side of the keyboard and trackpad. The adapter's settings are
# modules/nixos/bluetooth.nix and hid_apple is modules/nixos/keyboard, since
# both apply at the console too.

lib.mkIf config.desktop.enable {
  hardware.bluetooth.enable = true;

  # Pairing UI. The bar's Bluetooth item opens it.
  services.blueman.enable = true;

  # The trackpad is a libinput device. Its gestures and scroll direction are
  # Hyprland settings (modules/home/linux/desktop/hyprland.nix), since Hyprland
  # reads libinput itself rather than through X.
  services.libinput.enable = true;
}
