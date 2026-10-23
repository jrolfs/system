{ lib, pkgs, osConfig, ... }:

# Turns kanata's Mac-style ⌘ → Ctrl layer on for the Hyprland session, except
# while kitty is focused, and off again when the session ends so the text
# console never has it. The reasoning is in hypr-kanata-layers.rs, the layers
# in modules/nixos/keyboard/layout.kbd.

let
  # Window classes that keep the `plain` layer, where ⌘ is left alone.
  terminals = [ "kitty" ];

  hypr-kanata-layers = pkgs.rustTool {
    name = "hypr-kanata-layers";
    src = ./hypr-kanata-layers.rs;
  };

  command = arguments:
    lib.escapeShellArgs ([ (lib.getExe hypr-kanata-layers) (toString osConfig.keyboard.port) ] ++ arguments);
in
lib.mkIf ((osConfig.desktop.enable or false) && (osConfig.keyboard.enable or false)) {
  systemd.user.services.hypr-kanata-layers = {
    Unit = {
      Description = "Switch kanata layers with Hyprland's focused window";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = command ([ "follow" ] ++ terminals);
      # Stopping the session stops this before Hyprland's socket closes, so
      # the reset in `follow` never gets to run.
      ExecStopPost = command [ "set" "plain" ];
      # It exits when Hyprland's event socket closes, which is also what a
      # Hyprland restart looks like from here.
      Restart = "always";
      RestartSec = 2;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };
}
