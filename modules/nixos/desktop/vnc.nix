{ config, lib, ... }:

# WayVNC belongs to the existing user's graphical session, not a system-wide
# desktop or a second compositor. Home Manager starts it after uwsm imports
# that session's Wayland environment.

let
  cfg = config.desktop.vnc;
in
{
  options.desktop.vnc = {
    enable = lib.mkEnableOption "VNC control of the physical Hyprland desktop";

    output = lib.mkOption {
      type = lib.types.str;
      description = "Physical Hyprland output to share.";
      example = "HDMI-A-1";
    };

    passwordFile = lib.mkOption {
      type = lib.types.str;
      description = ''
        Absolute runtime path to a plaintext password, readable by the desktop
        user and outside the Nix store. Use a dedicated password of exactly
        eight ASCII letters or digits: legacy macOS VNC uses only eight bytes.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.desktop.enable;
        message = "desktop.vnc requires desktop.enable.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.passwordFile && !lib.hasPrefix builtins.storeDir cfg.passwordFile;
        message = "desktop.vnc.passwordFile must be an absolute path outside the Nix store.";
      }
    ];
  };
}
