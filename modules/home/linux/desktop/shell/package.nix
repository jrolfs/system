{ lib, runCommand }:

# The shell's config directory as a store path, the way `programs.quickshell.configs`
# wants it. Only the colours are generated: Palette.qml carries modules/theme/palette.nix
# into QML, so the shell matches everything else drawn from it without a theme engine at
# runtime. Buildable on its own, which is how the QML gets tried on irulan without a
# switch:
#
#   nix build --impure --expr \
#     '(import <nixpkgs> {}).callPackage ./modules/home/linux/desktop/shell/package.nix {}'
#   quickshell -p ./result

let
  palette = (import ../../../../theme/palette.nix).dark.soft;

  paletteQml = ''
    pragma Singleton
    import QtQuick
    import Quickshell

    Singleton {
    ${lib.concatStrings (
      lib.mapAttrsToList (name: hex: "    readonly property color ${name}: \"${hex}\"\n") palette
    )}}
  '';

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.fileFilter (
      file: lib.any file.hasExt [ "qml" "js" "conf" ] || file.name == "qmldir"
    ) ./.;
  };
in
runCommand "quickshell-shell" { passAsFile = [ "paletteQml" ]; inherit paletteQml; } ''
  cp -r ${src} $out
  chmod -R u+w $out
  cp $paletteQmlPath $out/theme/Palette.qml
''
