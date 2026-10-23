{ pkgs, inputs, ... }:

# Puts the `bootstrap` CLI on PATH so managing 1Password-backed secrets doesn't
# need a `nix run` prefix or a bootstrap checkout. Shared by darwin and NixOS:
# Irulan needs it as much as the Macs do.
#
# One binary with subcommands (`bootstrap secrets gpg import`) rather than one
# per area, so nothing generically named lands on PATH — in particular `gpg`
# can't shadow the real one.
#
# Working *on* the CLI is a different thing — `nix develop` in the bootstrap
# repo shadows this with a version that runs the working tree.

{
  environment.systemPackages = [
    inputs.bootstrap.packages.${pkgs.stdenv.hostPlatform.system}.bootstrap
  ];
}
