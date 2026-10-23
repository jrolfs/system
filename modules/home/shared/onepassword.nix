{ config, lib, pkgs, ... }:

# `op` the way an activation script can run it, which differs by platform.
# atuin.nix and claude-sync.nix read their login material through this.
#
# On the Macs it is the Homebrew CLI (1password-cli cask) at its absolute path,
# not pkgs._1password-cli: desktop-app integration (Touch ID authorization) is
# granted to that binary. The first read pops an authorization prompt, and a
# switch run with 1Password locked or signed out degrades to the caller's
# warning.
#
# Linux hosts are as often headless, with no desktop app to authorize against,
# so op signs in as a service account instead, with the token bootstrap
# installs at ~/.config/op/service-account-token (the same one arcade-scrape
# uses). Service accounts get the tightest rate limits 1Password sets, which
# suits callers that only read when nothing is configured yet. nixpkgs' op is
# enough for that: the setgid wrapper NixOS installs is for desktop-app
# integration, which a service account doesn't use.
#
# Both give a read two minutes before giving up, so a prompt nobody answers
# can't hang the switch.

let
  token = "${config.home.homeDirectory}/.config/op/service-account-token";

  op =
    if pkgs.stdenv.isDarwin then
      pkgs.writeShellScript "op" ''
        exec ${pkgs.coreutils}/bin/timeout 120 /opt/homebrew/bin/op --account rolfers.1password.com "$@"
      ''
    else
      pkgs.writeShellScript "op" ''
        if [ -z "''${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
          if [ ! -r ${token} ]; then
            echo "op: no 1Password service account token at ${token}" >&2
            exit 77
          fi
          OP_SERVICE_ACCOUNT_TOKEN=$(${pkgs.coreutils}/bin/cat ${token})
          export OP_SERVICE_ACCOUNT_TOKEN
        fi
        exec ${pkgs.coreutils}/bin/timeout 120 ${lib.getExe pkgs._1password-cli} "$@"
      '';
in
{
  options.onepassword.op = lib.mkOption {
    type = lib.types.path;
    readOnly = true;
    description = "An `op` command that authenticates without a terminal on this platform.";
  };

  config.onepassword.op = op;
}
