# The Node that one-off maintenance scripts run on, and the `audit` command
# that files them and keeps their output. Shared by this repo and rolfs.lan:
# this flake's `packages` and `devenvModules.audit` are built from here, and the
# root devenv.nix imports it directly.
#
# Node 26 is the current LTS and runs a `.ts` file as-is, stripping the types
# without a flag. Stripping is all it does, so a script can only use erasable
# syntax (no enums, namespaces or parameter properties) and has to name local
# imports with their `.ts` extension.
#
# The slim build because the scripts need `node` alone, and because the full
# nodejs_26 is not in the binary cache on aarch64-darwin, so it would compile.
{ pkgs }:

let
  nodejs = pkgs.nodejs-slim_26;
in
{
  inherit nodejs;

  audit = pkgs.writeShellApplication {
    name = "audit";
    runtimeInputs = [ nodejs pkgs.git ];
    text = ''exec node ${./audit.ts} "$@"'';
  };
}
