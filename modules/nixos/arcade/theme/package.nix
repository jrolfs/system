{ lib, runCommandLocal }:

# The game menu's Pegasus theme, as a store path for pegasus.nix to link into
# place. The QML beside this file is the theme. Only the values are generated:
# ui/Generated.js carries palette.nix, fonts.nix, style.nix and each system's
# tab label into QML, the way the desktop shell's package.nix carries the
# palette, so the station and the shell draw from the same numbers with no
# theme engine at runtime. Buildable on its own, which is how it gets tried
# headless on irulan without a switch:
#
#   nix build --impure --expr \
#     '(import <nixpkgs> {}).callPackage ./modules/nixos/arcade/theme/package.nix {}'

let
  palette = (import ../../../theme/palette.nix).dark.soft;
  fonts = import ../../../theme/fonts.nix;
  style = import ../../../theme/style.nix;
  systems = import ../systems.nix;

  values = {
    inherit palette style;
    fonts.sans = fonts.sans.family;
    labels = lib.mapAttrs (_: system: system.label) systems;

    # What only the station needs.
    station = {
      # The shell's sizes are for the desk-height glance it gets on this TV.
      # The station is read from the couch, so everything is a quarter larger.
      scale = 1.25;
      # Chosen by eye to match Hyprland's blur behind the shell (look.nix,
      # size 8 over 3 passes), and hyprland.nix's vibrancy of 0.17.
      blurRadius = 64;
      vibrancy = 0.17;
      # How long a game stays selected before the backdrop moves to its art,
      # so scrolling a list doesn't flicker through every screenshot.
      artDelay = 300;
    };
  };

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.fileFilter
      (file: lib.any file.hasExt [ "qml" "js" "cfg" ] || file.name == "qmldir")
      ./.;
  };
in
runCommandLocal "pegasus-theme-station"
  {
    generated = ''
      .pragma library
      var values = ${builtins.toJSON values};
    '';
    passAsFile = [ "generated" ];
  }
  ''
    cp -r ${src} $out
    chmod -R u+w $out
    cp $generatedPath $out/ui/Generated.js

    # The desktop's wallpaper, which the shell's glass blurs too.
    mkdir -p $out/assets
    cp ${../../../../media/wallpapers/black-ii-gruvbox-material.jpg} $out/assets/wallpaper.jpg
  ''
