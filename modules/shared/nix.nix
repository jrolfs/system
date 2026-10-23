{ inputs, ... }:

# Nix and nixpkgs settings that read the same in nix-darwin and NixOS. What
# stays per platform is where the option names differ (garbage collection and
# store optimisation) or the value does (nix.package: the Macs pin Lix 2.94 for
# devbox).

let
  overlays = import ../../overlays inputs;
in
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # So `nix shell nixpkgs#foo` and `nix-shell -p foo` resolve to the nixpkgs
  # this system was built from, rather than whatever the global registry or a
  # channel says. Each platform adds its own entries alongside these.
  nix.registry.nixpkgs.flake = inputs.nixpkgs;
  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

  # modules/home is shared by both platforms and reaches for overlay packages
  # unconditionally (claude-helpers, zshcs), so a host without the overlay
  # doesn't evaluate at all. Packages in it that only make sense on macOS are
  # lazy: nothing builds unless something references it.
  nixpkgs.overlays = [ overlays ];

  nixpkgs.config = {
    allowBroken = true;
    allowUnfree = true;
    allowUnsupportedSystem = true;
  };
}
