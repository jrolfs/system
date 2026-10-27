{ lib, osConfig, ... }:

# Vicinae, on ⌘⌥Space: Raycast's role on the Macs, and close enough in design
# that the habits carry over. ⌘Space is the shell's own launcher now; this
# stays for its extensions.
#
# Runs as a user service so ⌘⌥Space only has to show a window that already
# exists. Hyprland blurs behind it (hyprland.nix), so the window's own
# opacity here is what sets how much of the desktop shows through.

let
  palette = (import ../../../theme/palette.nix).dark.soft;
  fonts = import ../../../theme/fonts.nix;

  rounding = 10;
  # Fairly opaque, since the launcher is read closely.
  opacity = 0.88;
in
lib.mkIf (osConfig.desktop.enable or false) {
  programs.vicinae = {
    enable = true;
    systemd = {
      enable = true;
      autoStart = true;
    };

    themes.gruvbox-material-dark-soft = {
      meta = {
        name = "Gruvbox Material Dark Soft";
        description = "From modules/theme/palette.nix";
        variant = "dark";
        inherits = "vicinae-dark";
      };

      colors = {
        core = {
          background = palette.bg0;
          foreground = palette.fg0;
          secondary_background = palette.bg1;
          border = palette.bg3;
          accent = palette.yellow;
          accent_foreground = palette.bg0;
        };

        accents = {
          blue = palette.blue;
          green = palette.green;
          magenta = palette.purple;
          orange = palette.orange;
          purple = palette.purple;
          red = palette.red;
          yellow = palette.yellow;
          cyan = palette.aqua;
        };

        text = {
          default = palette.fg0;
          muted = palette.grey2;
          placeholder = palette.grey1;
          danger = palette.red;
          success = palette.green;
          selection = {
            background = palette.bg_visual_yellow;
            foreground = palette.fg1;
          };
        };
      };
    };

    settings = {
      theme.dark.name = "gruvbox-material-dark-soft";
      theme.light.name = "gruvbox-material-dark-soft";

      font.normal.family = fonts.sans.family;

      # No tray: the shell has no tray area to put it in.
      tray.enabled = false;

      telemetry.system_info = false;

      launcher_window = {
        inherit opacity rounding;
        material = "blur";
      };
    };
  };
}
