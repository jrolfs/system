{ config, lib, pkgs, ... }:

# What the TV shows after a boot. Only the starting point: whichever sessions
# are installed stay startable afterwards with `station` and `desktop`
# (switch.nix), whatever this says.
#
#   desktop  greetd's log-in screen on tty1. The station starts on demand.
#   arcade   the station starts at boot and its terminal is the one shown.
#            greetd still runs on tty1 behind it.
#   console  neither: a text log-in on tty1, both started on demand.
#
# Written against greetd only through `services.greetd.enable`, so it works
# with or without the desktop.

let
  inherit (lib) mkIf mkMerge mkForce;

  cfg = config.sessions;
  arcade = config.arcade;
  greetd = config.services.greetd.enable;
in
{
  options.sessions.boot = lib.mkOption {
    type = lib.types.enum [ "desktop" "arcade" "console" ];
    default = "desktop";
    description = "What the screen shows after boot.";
  };

  config = mkMerge [
    {
      assertions = [{
        assertion = cfg.boot != "arcade" || arcade.enable;
        message = "sessions.boot = \"arcade\" needs arcade.enable.";
      }];
    }

    (mkIf (cfg.boot == "arcade" && arcade.enable) {
      systemd.defaultUnit = "graphical.target";
      systemd.services.arcade-station.wantedBy = [ "graphical.target" ];

      # Starting a service on a VT doesn't make that VT the visible one, and
      # greetd comes up on tty1 in the same boot. This switches once, at boot
      # only: the station restarting later after a crash shouldn't pull the
      # screen away from whoever is using the desktop.
      systemd.services.arcade-boot-vt = {
        description = "Show the emulator station after boot";
        after = [ "arcade-station.service" ] ++ lib.optional greetd "greetd.service";
        wants = [ "arcade-station.service" ];
        wantedBy = [ "graphical.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.kbd}/bin/chvt ${toString arcade.vt}";
        };
      };
    })

    (mkIf (cfg.boot == "console") {
      # greetd is wanted by graphical.target, so not reaching it is what keeps
      # greetd from starting while leaving it startable.
      systemd.defaultUnit = mkForce "multi-user.target";
    })

    # greetd switches off the text log-in on tty1 (autovt@tty1) so a rebuild
    # can't restart a getty over it. Without greetd running at boot, that
    # leaves tty1 blank, so it comes back for a console boot.
    #
    # As a drop-in: autovt@tty1 is an instance of a template, so by default
    # NixOS writes this out as a whole unit file with nothing to run, which
    # replaced the real getty and left tty1 blank anyway.
    #
    # Started once at boot, not wanted by getty.target. A switch starts every
    # active target again, so with the want, each switch after `desktop`
    # brought the getty back and stopped greetd, which conflicts with it.
    # nixpkgs' getty module leaves that want out whenever a display manager is
    # enabled, for the same reason. This unit stays active once it has run, so
    # a switch has nothing to start.
    (mkIf (cfg.boot == "console" && greetd) {
      systemd.services."autovt@tty1" = {
        enable = mkForce true;
        overrideStrategy = "asDropin";
      };

      systemd.services.console-login = {
        description = "Text log-in on tty1 after a console boot";
        wantedBy = [ "multi-user.target" ];
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${config.systemd.package}/bin/systemctl start --no-block autovt@tty1.service";
        };
      };
    })
  ];
}
