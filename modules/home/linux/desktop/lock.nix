{ lib, osConfig, ... }:

# The lock screen, and what locks it.
#
# hypridle is here for its lock handling only: `loginctl lock-session` (the ⌘Esc
# binding) and suspend both ask logind to lock, and something in the session
# has to answer by starting hyprlock. There are deliberately no idle timeouts,
# since this machine spends long stretches showing video with nobody touching
# the keyboard.

let
  palette = (import ../../../theme/palette.nix).dark.soft;
  fonts = import ../../../theme/fonts.nix;

  rgb = hex: "rgb(${lib.removePrefix "#" hex})";

  rounding = 10;
in
lib.mkIf (osConfig.desktop.enable or false) {
  services.hypridle = {
    enable = true;
    settings.general = {
      lock_cmd = "pidof hyprlock || hyprlock";
      before_sleep_cmd = "loginctl lock-session";
      after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'";
    };
  };

  programs.hyprlock = {
    enable = true;
    settings = {
      general.hide_cursor = true;

      background = [
        {
          path = "screenshot";
          blur_passes = 3;
          blur_size = 8;
          color = rgb palette.bg_dim;
        }
      ];

      label = [
        {
          text = "$TIME12";
          font_family = fonts.sans.family;
          font_size = 72;
          color = rgb palette.fg1;
          position = "0, 160";
          halign = "center";
          valign = "center";
        }
      ];

      input-field = [
        {
          size = "280, 48";
          rounding = rounding;
          outline_thickness = 2;
          font_family = fonts.sans.family;
          outer_color = rgb palette.bg3;
          inner_color = rgb palette.bg0;
          font_color = rgb palette.fg1;
          check_color = rgb palette.yellow;
          fail_color = rgb palette.red;
          placeholder_text = "Password";
          fade_on_empty = false;
          position = "0, -20";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };
}
