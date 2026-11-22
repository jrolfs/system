# The shell for working in this repo: Node and `audit` for maintenance scripts
# (see devenv/audit/default.nix and "Maintenance scripts" in CLAUDE.md).
#
# Built from the nixpkgs in flake.lock rather than devenv's own, so the Node
# here is the store path this flake exports to rolfs.lan and that nix-switch
# already has, and there is no second nixpkgs to keep current. The kitty
# devenv.nix does the same.
{ pkgs, ... }:

let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  nixpkgs = lock.nodes.${lock.nodes.root.inputs.nixpkgs}.locked;
  system = import (builtins.fetchTree nixpkgs) { inherit (pkgs.stdenv.hostPlatform) system; };
  tools = import ./devenv/audit { pkgs = system; };
in
{
  packages = [ tools.nodejs tools.audit ];
}
