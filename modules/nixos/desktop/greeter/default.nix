{ config, lib, pkgs, userName, ... }:

# greetd on tty1, showing a login screen drawn by Quickshell in the same glass
# and Gruvbox Material as the desktop's own lock screen, so logging out and
# locking look like one thing. greetd only speaks a socket protocol, so the
# greeter needs a compositor of its own: a bare Hyprland, run as the `greeter`
# user with greeter.lua as its whole configuration, whose one job is to run
# the QML in ./qml and exit when it does.
#
# What this is built around is a black screen at boot with nobody able to log
# in. greetd gives up for good when its greeter exits without having started a
# session ("greeter exited without creating a session"), and NixOS restarts it
# only after a clean exit. So a crashed Quickshell is restarted in place, and
# if Hyprland itself can't come up, or Quickshell keeps crashing, the same tty
# falls back to agreety, greetd's text greeter, rather than to nothing.
#
# By default it shows the login screen. desktop.autoLogin skips it, and even
# then `initial_session` is only a default, for whatever owns the choice of
# what the machine boots into (sessions.boot) to override.

let
  palette = (import ../../../theme/palette.nix).dark.soft;

  hyprland = config.programs.hyprland.package;
  systemctl = "${config.systemd.package}/bin/systemctl";

  # The session uwsm generates for Hyprland, the same one autoLogin starts.
  session = [ (lib.getExe config.programs.uwsm.package) "start" "hyprland-uwsm.desktop" ];

  user = config.users.users.${userName};
  displayName =
    if user.description != "" then user.description
    else lib.toUpper (lib.substring 0 1 userName) + lib.substring 1 (lib.stringLength userName) userName;

  # Owned by the greeter user, whose home is /var/empty. Quickshell and Mesa
  # want somewhere to write their state and shader caches, and the marker
  # below lives here too.
  stateDirectory = "/var/lib/quickshell-greeter";

  # Written by the QML only once greetd has accepted the session to start, so
  # the scripts below can tell "logged in, done" from "crashed".
  marker = "${stateDirectory}/launched";

  paletteQml = ''
    pragma Singleton
    import QtQuick
    import Quickshell

    Singleton {
    ${lib.concatStrings (
      lib.mapAttrsToList (name: hex: "    readonly property color ${name}: \"${hex}\"\n") palette
    )}}
  '';

  # Everything the QML needs from the system, as values: the greeter can't
  # read the user's home, and shouldn't have to find anything on PATH.
  settingsQml = ''
    pragma Singleton
    import QtQuick
    import Quickshell

    Singleton {
        readonly property string userName: ${builtins.toJSON userName}
        readonly property string displayName: ${builtins.toJSON displayName}
        readonly property string avatar: ${builtins.toJSON "file:///var/lib/AccountsService/icons/${userName}"}
        readonly property string wallpaper: ${builtins.toJSON "file://${../../../../media/wallpapers/black-ii-gruvbox-material.jpg}"}
        readonly property var session: ${builtins.toJSON session}
        readonly property string systemctl: ${builtins.toJSON systemctl}
        readonly property string touch: ${builtins.toJSON "${pkgs.coreutils}/bin/touch"}
    }
  '';

  qml = pkgs.runCommand "quickshell-greeter-qml" {
    inherit paletteQml settingsQml;
    passAsFile = [ "paletteQml" "settingsQml" ];
  } ''
    cp -r ${./qml} $out
    chmod -R u+w $out
    cp $paletteQmlPath $out/Colors.qml
    cp $settingsQmlPath $out/Settings.qml
  '';

  # Run inside the greeter's Hyprland. Quickshell exiting without the marker
  # is a crash, since the QML never quits on its own otherwise, and a retry
  # keeps the screen from ending in agreety over one bad frame. Three tries,
  # so a greeter that can't start at all still reaches the fallback.
  inside = pkgs.writeShellApplication {
    name = "quickshell-greeter-session";
    runtimeInputs = [ pkgs.quickshell hyprland ];
    text = ''
      for _ in 1 2 3; do
        quickshell --path ${qml} || true
        [[ -e ${marker} ]] && break
        sleep 1
      done
      hyprctl dispatch 'hl.dsp.exit()'
    '';
  };

  hyprlandConfig = pkgs.replaceVars ./greeter.lua {
    session = lib.getExe inside;
    background = "rgb(${lib.removePrefix "#" palette.bg_dim})";
  };

  greeter = pkgs.writeShellApplication {
    name = "quickshell-greeter";
    runtimeInputs = [ hyprland config.services.greetd.package pkgs.coreutils ];
    text = ''
      rm -f ${marker}
      export GREETER_MARKER=${marker}
      export XDG_STATE_HOME=${stateDirectory}/state
      export XDG_CACHE_HOME=${stateDirectory}/cache

      # Stylix exports these from /etc/profile, which greetd sources before
      # starting the greeter as much as before a session.
      # The QML draws all of itself, and a platform theme or style that
      # can't load here only adds warnings and startup time.
      unset QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE

      # Hyprland rather than start-hyprland: the watchdog restarts a crashed
      # compositor in a safe mode with Hyprland's stock configuration, binds
      # and all, which here would be a desktop running as `greeter`.
      Hyprland --config ${hyprlandConfig} || true

      [[ -e ${marker} ]] && exit 0

      echo "The login screen failed to start. Logging in at the console instead."
      exec agreety --cmd ${lib.escapeShellArg (lib.concatStringsSep " " session)}
    '';
  };
in
lib.mkIf config.desktop.enable {
  services.greetd = {
    enable = true;
    settings.default_session.command = lib.getExe greeter;

    settings.initial_session = lib.mkIf config.desktop.autoLogin (lib.mkDefault {
      user = userName;
      command = lib.concatStringsSep " " session;
    });
  };

  systemd.tmpfiles.rules = [
    "d ${stateDirectory} 0750 greeter greeter -"
    "d ${stateDirectory}/state 0700 greeter greeter -"
    "d ${stateDirectory}/cache 0700 greeter greeter -"
  ];

  # logind lets the active local session power the machine off without asking,
  # the greeter's included, until another user is logged in: an SSH session,
  # or the emulator station's. Then it wants an administrator's password,
  # which nothing in the greeter can ask for, and the power buttons silently
  # do nothing. Only for the greeter user, only while it holds the screen.
  security.polkit.enable = true;
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      var actions = [
        "org.freedesktop.login1.power-off",
        "org.freedesktop.login1.power-off-multiple-sessions",
        "org.freedesktop.login1.reboot",
        "org.freedesktop.login1.reboot-multiple-sessions",
        "org.freedesktop.login1.suspend",
        "org.freedesktop.login1.suspend-multiple-sessions",
      ];

      if (subject.user == "greeter" && subject.local && subject.active
          && actions.indexOf(action.id) >= 0) {
        return polkit.Result.YES;
      }
    });
  '';
}
