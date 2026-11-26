{ config, lib, pkgs, osConfig, ... }:

# The desktop shell: island bar, launcher, control center, notifications, OSD,
# lock screen, polkit agent and the wallpaper, all one Quickshell config. It
# replaces mako, hyprpolkitagent, hyprlock and the old bar, so none of those
# run beside it: two notification servers or two polkit agents fight over the
# same DBus name, and whichever loses goes quiet.
#
# The QML is the tree beside this file, built into a store path by
# package.nix. This module installs it and supplies what the QML assumes is
# around it.

let
  fonts = import ../../../../theme/fonts.nix;
  look = import ../look.nix;

  wallpapers = ../../../../../media/wallpapers;

  shell = pkgs.callPackage ./package.nix { };

  # The shell starts its helpers by bare name. Under the systemd unit, PATH is
  # whatever the user manager was handed, which need not include the profile
  # these would otherwise come from, and a missing one fails silently: the
  # visualiser stays flat, Night Light never warms.
  runtimePath = lib.makeBinPath [
    osConfig.programs.hyprland.package # hyprctl
    osConfig.programs.uwsm.package
    osConfig.systemd.package # systemctl, matching the running manager
    pkgs.bash
    pkgs.brightnessctl
    pkgs.cava
    pkgs.cliphist
    pkgs.coreutils
    pkgs.ddcutil
    pkgs.grim
    pkgs.hyprsunset
    pkgs.procps # pkill
    pkgs.wl-clipboard
  ];

  # Stylix's Qt target sets QT_QPA_PLATFORMTHEME and QT_STYLE_OVERRIDE for the
  # session, to theme Qt apps through qt5ct and Kvantum. The shell is a Qt app
  # that draws every pixel itself, and a platform theme loaded underneath it
  # only changes its dialogs' fonts and its startup time. Unset in the wrapper
  # rather than the unit, so `quickshell ipc` from a terminal and the shell
  # started by hand behave the same as the service.
  quickshell = pkgs.symlinkJoin {
    name = "quickshell-${pkgs.quickshell.version}-wrapped";
    paths = [ pkgs.quickshell ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for program in $out/bin/*; do
        wrapProgram "$program" \
          --prefix PATH : ${runtimePath} \
          --unset QT_QPA_PLATFORMTHEME \
          --unset QT_STYLE_OVERRIDE
      done
    '';
    meta.mainProgram = "quickshell";
  };

  # What Nix declares of the shell's settings. The shell keeps them in a file
  # it also writes from its Settings window, so this is copied over that file
  # on every switch rather than linked: a read-only store symlink would make
  # the window's writes fail, and a file written once would let the window's
  # changes outlive the declaration. Keys left out here take the defaults in
  # config/Config.qml.
  settings = {
    fontBody = fonts.sans.family;
    fontDisplay = fonts.sans.family;

    wallpaper = "${wallpapers}/black-ii-gruvbox-material.jpg";
    wallpaperDir = "${wallpapers}";

    # Game Mode zeroes these in Hyprland and later puts these values back, and
    # the island sizes its exclusive zone from gapsOut.
    hyprGapsIn = look.gapsIn;
    hyprGapsOut = look.gapsOut;
    hyprRounding = look.rounding;

    # 12-hour, like every other clock this repo configures.
    clock24h = false;

    # A password field with nothing in it as you type reads as a field that
    # isn't taking input.
    lockShowDots = true;

    # The rounded screen corners imitate a laptop panel. A TV's picture is
    # square to its bezel, so on Irulan they only clip the wallpaper.
    screenCorners = false;

    # Without the Wi-Fi tile: Irulan is wired and runs no NetworkManager for
    # it to talk to.
    ccLayout = builtins.toJSON {
      v = 2;
      columns = 7;
      items = [
        { key = "bluetooth"; x = 0; y = 0; w = 3; h = 1; }
        { key = "focus"; x = 3; y = 0; w = 3; h = 1; }
        { key = "lock"; x = 6; y = 0; w = 1; h = 1; }
        { key = "gamemode"; x = 0; y = 1; w = 3; h = 1; }
        { key = "nightlight"; x = 3; y = 1; w = 4; h = 1; }
        { key = "sound"; x = 0; y = 2; w = 7; h = 1; }
        { key = "display"; x = 0; y = 3; w = 7; h = 1; }
        { key = "notifications"; x = 0; y = 4; w = 7; h = 3; }
      ];
    };
  };

  settingsFile = (pkgs.formats.json { }).generate "quickshell-settings.json" settings;
  settingsDirectory = "${config.xdg.stateHome}/quickshell";
in
lib.mkIf (osConfig.desktop.enable or false) {
  programs.quickshell = {
    enable = true;
    package = quickshell;
    configs.shell = shell;
    activeConfig = "shell";
    systemd.enable = true;
  };

  systemd.user.services.quickshell.Unit = {
    PartOf = [ config.programs.quickshell.systemd.target ];
    # A switch points the config symlink at a new store path. Naming that path
    # here changes the unit along with it, so the switch restarts the shell onto
    # the new QML instead of leaving it running the old tree until next login.
    # The settings file needs no such help: the shell watches it.
    X-Restart-Triggers = [ "${shell}" ];
  };

  home.activation.quickshellSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] # bash
    ''
      run mkdir -p ${lib.escapeShellArg settingsDirectory}
      run install -m 0644 ${settingsFile} ${lib.escapeShellArg "${settingsDirectory}/settings.json"}
    '';

  # The launcher's `:` mode lists this history.
  services.cliphist.enable = true;
}
