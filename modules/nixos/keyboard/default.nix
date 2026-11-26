{ config, lib, ... }:

# kanata, doing on Linux what Karabiner-Elements does on the Macs: Caps is
# Ctrl (Escape on its own), Tab held makes hjkl arrows, right ⌥ is Hyper. The
# layout is layout.kbd, written so the same file loads on both.
#
# Its own option rather than part of desktop.enable, because none of that
# needs a desktop. kanata reads the keyboard below the display server and
# writes to a virtual one through uinput, so the same layout applies at the
# text console, at the greeter and in Hyprland alike. The Mac-style ⌘ → Ctrl
# remapping is the exception, and is only switched on inside Hyprland (see the
# `mac` layer in layout.kbd and modules/home/linux/desktop/kanata-layers.nix).
#
# A system service rather than a user one because it reads /dev/input and
# writes /dev/uinput, which the module grants to its own dedicated user.

let
  cfg = config.keyboard;
in
{
  options.keyboard = {
    enable = lib.mkEnableOption "the Mac-style keyboard layout (kanata)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 10000;
      description = ''
        Local TCP port kanata listens on for layer changes. The desktop
        session uses it to switch the ⌘ remapping on and off.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # hid_apple drives the Magic Keyboard, over USB and Bluetooth alike.
    # fnmode=1 puts media keys on the top row and F1–F12 behind Fn, as on a
    # Mac. The kernel's default, 3, only picks that for keyboards it recognises
    # as Apple's, and falls back to F-keys first for anything else, so this pins
    # it rather than trusting the device table to know every model. ⌘ and ⌥
    # already arrive as Super and Alt, which is what layout.kbd and the Hyprland
    # bindings expect, so nothing is swapped.
    boot.extraModprobeConfig = ''
      options hid_apple fnmode=1
    '';

    services.kanata = {
      enable = true;

      keyboards.main = {
        # Every keyboard rather than a named device: a Bluetooth keyboard's
        # event node is created afresh each time it reconnects, so there is no
        # stable path to name.
        devices = [ ];

        config = builtins.readFile ./layout.kbd;

        # Keys outside defsrc pass through either way. This makes kanata see
        # them too, so Caps or Tab held into a key layout.kbd doesn't list
        # (Caps with `, say) still resolves as a hold rather than arriving as
        # an Escape after the other key.
        extraDefCfg = "process-unmapped-keys yes";

        inherit (cfg) port;
      };
    };
  };
}
