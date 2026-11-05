{ lib, pkgs, osConfig, ... }:

# An explicit runtime config keeps the password out of both the Nix store and
# argv. The wrapper validates it before starting WayVNC, so a missing or
# malformed credential never turns into unauthenticated desktop access.

let
  cfg = osConfig.desktop.vnc;
  start = pkgs.writeShellApplication {
    name = "wayvnc-start";
    runtimeInputs = [ pkgs.wayvnc ];
    text = builtins.readFile ./wayvnc-start.sh;
  };
in
lib.mkIf (osConfig.desktop.vnc.enable or false) {
  home.packages = [ pkgs.wayvnc ];

  systemd.user.services.wayvnc = {
    Unit = {
      Description = "Share the physical Hyprland desktop over VNC";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      # The system renderer and user manager cannot order each other's units.
      # Retry locally if login races the first credential render, without
      # making another 1Password request.
      StartLimitIntervalSec = 0;
    };

    Service = {
      ExecStart = lib.escapeShellArgs [ (lib.getExe start) cfg.output ];
      LoadCredential = [ "password:${cfg.passwordFile}" ];
      RuntimeDirectory = "wayvnc";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };
}
