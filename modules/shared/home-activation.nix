{ config, lib, pkgs, ... }:

# One user's home-manager activation on its own, for `nix-switch --home`. A full
# switch runs it as one step of the system's activation, through a wrapper the
# home-manager integration writes inline and does not expose, so this rebuilds
# that wrapper from the same options. Without them the activation would run
# with no backup command, and an unmanaged file in the way of a link would
# abort it, as home-backup.nix explains.
#
# The environment mirrors the nix-darwin wrapper in home-manager's
# nix-darwin/default.nix. The NixOS integration runs the same activation from a
# systemd unit, which also sets QT_QPA_PLATFORM=offscreen for KDE's tools,
# and nothing here uses those.
#
# `generation` is beside the wrapper so nix-switch can tell whether
# home.packages changed. With useUserPackages those land in the system's
# per-user profile rather than home-manager's own, so this activation alone
# leaves the commands on PATH as they were.

let
  cfg = config.home-manager;

  driverVersion = if cfg.enableLegacyProfileManagement then "0" else "1";

  activation = username: user:
    pkgs.linkFarm "home-activation-${username}" [
      {
        name = "activate";
        path = pkgs.writeShellScript "home-activation-${username}" ''
          ${lib.optionalString (cfg.backupFileExtension != null)
            "export HOME_MANAGER_BACKUP_EXT=${lib.escapeShellArg cfg.backupFileExtension}"}
          ${lib.optionalString (cfg.backupCommand != null)
            "export HOME_MANAGER_BACKUP_COMMAND=${lib.escapeShellArg cfg.backupCommand}"}
          ${lib.optionalString cfg.overwriteBackup "export HOME_MANAGER_BACKUP_OVERWRITE=1"}
          ${lib.optionalString cfg.verbose "export VERBOSE=1"}
          exec ${user.home.activationPackage}/activate --driver-version ${driverVersion}
        '';
      }
      {
        name = "generation";
        path = user.home.activationPackage;
      }
    ];
in
{
  system.build.homeActivation = lib.mapAttrs activation cfg.users;
}
