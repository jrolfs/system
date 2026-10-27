{ lib, ... }:

# A graphical desktop for a NixOS host that has a screen and a keyboard:
# Hyprland under uwsm, started from greetd. The keyboard layout is separate,
# in modules/nixos/keyboard, since it applies without a desktop too.
#
# An option rather than an import that does everything, so a host can carry
# this whole tree and still be headless, and so the home-manager side
# (modules/home/linux/desktop) can read `osConfig.desktop.enable` and stay out of
# the way on a server.

{
  options.desktop.enable = lib.mkEnableOption "the Hyprland desktop";

  # Off by default: with it on, whoever is at the screen when the machine
  # starts is in this user's session, sudo and all, with no password asked.
  options.desktop.autoLogin = lib.mkEnableOption
    "logging straight into the desktop at boot, without the login screen";

  imports = [
    ./apps.nix
    ./greeter.nix
    ./input.nix
    ./session.nix
    ./stylix.nix
    ./user-picture.nix
  ];
}
