# kitty runs these kittens and extensions in its own Python, frozen into the
# app bundle with no source a language server could read. The nixpkgs build of
# the same kitty release has that source, so it goes on PYTHONPATH, where
# basedpyright picks it up from the interpreter's sys.path.
#
# Everything comes from the nixpkgs revision the system itself is built from,
# so kitty here moves with the one nix-switch installs rather than with a
# second lock file. The kitty in /Applications is the Homebrew cask, which
# upgrades on its own schedule; a release or two of drift only matters if the
# API used here changed.
{ pkgs, ... }:
let
  lock = builtins.fromJSON (builtins.readFile ../../../../flake.lock);
  nixpkgs = lock.nodes.${lock.nodes.root.inputs.nixpkgs}.locked;
  system = import (builtins.fetchTree nixpkgs) { inherit (pkgs.stdenv.hostPlatform) system; };
in
{
  # kitty 0.49 embeds Python 3.14.
  packages = [
    system.python314
    system.basedpyright
    system.ruff
  ];

  env.PYTHONPATH = "${system.kitty.src}";

  # Read by the nvim config: only these servers start for files under here.
  env.NVIM_LSP_SERVERS = "basedpyright ruff";
}
