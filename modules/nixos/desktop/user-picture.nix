{ config, lib, hostname, userName, ... }:

# The account picture, the Linux half of modules/darwin/user-picture.nix, and
# much less work, because nothing here is trying to sync it from an account in
# the cloud.
#
# AccountsService is what asks on this side: greeters and the desktops' own
# settings panels read it over DBus rather than touching the home directory. It
# keeps per-user state under /var/lib/AccountsService, where an account whose
# keyfile carries no `Icon=` falls back to icons/<user>. So the image is the
# whole declaration, and the keyfile stays the daemon's, which rewrites it as
# sessions come and go.
#
# ~/.face is the older convention and still the one anything that reads the
# home directory instead of DBus will look for, so it gets the same image.
#
# Behind desktop.enable, on the same reasoning apps.nix makes: a headless host
# has nothing to draw this on.

let
  avatar = ../../../media/avatars/${hostname}.png;
in
lib.mkIf config.desktop.enable {
  # L+ rather than C, so a picture changed in a desktop's own settings goes
  # back to the declared one on the next switch. A declaration that quietly
  # loses to the GUI is worse than no declaration.
  systemd.tmpfiles.rules = lib.optionals (builtins.pathExists avatar) [
    "d /var/lib/AccountsService 0755 root root -"
    "d /var/lib/AccountsService/icons 0755 root root -"
    "L+ /var/lib/AccountsService/icons/${userName} - - - - ${avatar}"
    "L+ ${config.users.users.${userName}.home}/.face - - - - ${avatar}"
  ];
}
