{ config, lib, pkgs, ... }:

# Stylix: one base16 scheme, font set, cursor and icon theme for everything on
# the desktop that has no theme of its own. Before it, each new GTK or Qt app
# came up in Adwaita or Fusion until someone wrote it a theme by hand.
#
# autoEnable stays on, with the opt-outs below, rather than off with a list of
# opt-ins. Theming everything is the point; the exceptions are the few apps
# already themed by hand from modules/theme/palette.nix, and it's those a
# Stylix target would clobber, not the long tail it covers. A new app is
# themed by default, and a hand-made theme only needs its one line here.
#
# The scheme is the published Gruvbox Material Dark Soft rather than one built
# from palette.nix: base16 has 16 slots where the palette has its own names, so
# a mapping would be ours to maintain and would still land in the same place.

let
  fonts = import ../../theme/fonts.nix;

  fontPackage = font: lib.getAttrFromPath (lib.splitString "." font.package) pkgs;
  sans = {
    package = fontPackage fonts.sans;
    name = fonts.sans.family;
  };
in
lib.mkIf config.desktop.enable {
  stylix = {
    enable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-material-dark-soft.yaml";
    polarity = "dark";

    # The shell paints the wallpaper itself (modules/home/linux/desktop/shell).
    # This is here for the targets that derive from it, not to draw it: with
    # the Hyprland target off, nothing Stylix runs puts it on screen.
    image = ../../../media/wallpapers/black-ii-gruvbox-material.jpg;

    fonts = {
      sansSerif = sans;
      # fonts.nix has no serif face, and Geist reads better than a stray one.
      serif = sans;
      monospace = {
        package = fontPackage fonts.mono;
        name = fonts.mono.family;
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
      # What GTK apps used before Stylix, rather than its 12.
      sizes.applications = 11;
    };

    cursor = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
    };

    icons = {
      enable = true;
      package = pkgs.papirus-icon-theme;
      dark = "Papirus-Dark";
      light = "Papirus-Light";
    };

    opacity.popups = 0.85;

    targets = {
      # Custom colours in modules/nixos/default.nix, chosen for how the Linux
      # console uses slots 0 and 7.
      console.enable = false;
      # The greeter is the shell's own QML now (greeter/), but if ReGreet ever
      # comes back it should match the lock screen, not base16.
      regreet.enable = false;
      # Nothing here uses nixvim or nvf, but if one arrives it should follow
      # the neovim config's own theme, as the HM neovim target does below.
      nixvim.enable = false;
      nvf.enable = false;
    };
  };

  home-manager.sharedModules = [
    {
      stylix.targets = {
        # Their own Gruvbox Material themes, the same ones the Macs use.
        kitty.enable = false;
        zed.enable = false;
        neovim.enable = false;
        neovide.enable = false;
        nixvim.enable = false;
        nvf.enable = false;
        vim.enable = false;

        # Themed from palette.nix in vicinae.nix.
        vicinae.enable = false;

        # hyprland.nix writes hyprland.lua directly, so this target's
        # wayland.windowManager.hyprland settings would land in a file Hyprland
        # doesn't read. Its hyprpaper half would start a second wallpaper
        # under the shell's.
        hyprland.enable = false;
        hyprpaper.enable = false;

        # Replaced by the shell, and themed by it if they ever come back.
        hyprlock.enable = false;
        mako.enable = false;

        # Deliberately on the `system` theme, which follows the terminal's
        # colours (opencode.nix).
        opencode.enable = false;
        # starship.toml names terminal colours, which kitty already maps to
        # Gruvbox Material. This target swaps in a palette of its own, so the
        # prompt would differ from the Macs'.
        starship.enable = false;

        # Each builds a theme for a desktop that isn't running, and an autostart
        # entry to apply it at every login; KDE's also prepends its config to
        # XDG_CONFIG_DIRS for the whole session. hyprland.nix sets the two
        # dconf keys from GNOME's that matter outside GNOME.
        gnome.enable = false;
        kde.enable = false;

        # No rofi here, and its target sets a renamed rofi option regardless,
        # which warns on every build.
        rofi.enable = false;
      };
    }
  ];
}
