{ lib, osConfig, ... }:

# Notifications, drawn by mako in the top right, under the bar.

let
  palette = (import ../../../theme/palette.nix).dark.soft;
  fonts = import ../../../theme/fonts.nix;

  rounding = 10;
  opacity = "e6";
in
lib.mkIf (osConfig.desktop.enable or false) {
  services.mako = {
    enable = true;
    settings = {
      font = "${fonts.sans.family} 11";
      anchor = "top-right";
      margin = "12";
      padding = "12,14";
      width = 360;
      border-size = 1;
      border-radius = rounding;
      default-timeout = 6000;

      background-color = "${palette.bg0}${opacity}";
      text-color = palette.fg1;
      border-color = palette.bg3;
      progress-color = "over ${palette.bg3}";

      "urgency=critical" = {
        border-color = palette.red;
        default-timeout = 0;
      };
    };
  };
}
