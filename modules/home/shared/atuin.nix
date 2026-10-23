{ pkgs, lib, config, ... }:

# Logs atuin into the sync server on a machine that hasn't yet. The login
# material lives in one 1Password item — op://Secrets/Atuin, recorded as
# `atuin-key` in the bootstrap repo's secrets.json — with username/password for
# the account and a `key` field holding the encryption key (`atuin key` output).
#
# The key goes in on stdin rather than argv: with --username/--password given
# and --key absent, `atuin login` reads the encryption key as a single line
# from stdin (both the legacy and hub login paths), so it never shows up in a
# process listing. Non-interactively a wrong key is a logout-and-fail, not a
# retry prompt, so a bad value can't wedge the switch.
#
# The reads go through onepassword.nix, which authorizes through the desktop
# app on the Macs and a service account on Linux. Either way a switch that
# can't reach 1Password degrades to a warning.

let
  item = "op://Secrets/Atuin";

  login = pkgs.writeShellScript "atuin-login" ''
    set -uo pipefail

    export PATH=${lib.makeBinPath [ pkgs.atuin pkgs.coreutils ]}:$PATH

    # Ask atuin whether it is logged in rather than testing for a file it
    # writes. This used to check $XDG_DATA_HOME/atuin/session, which the hub
    # login path never creates — it records the token as a `hub_session` row in
    # meta.db — so the guard never fired and every switch ran the three `op
    # read` calls below, each one a Touch ID prompt.
    #
    # The check is local: atuin resolves the session for the configured sync
    # address without contacting it (an unreachable address still fails in
    # ~10ms with "Not logged in"), so this stays correct offline and can't
    # stall the switch. It also doesn't need XDG_DATA_HOME, which activation
    # runs without.
    atuin status >/dev/null 2>&1 && exit 0

    op() { ${config.onepassword.op} "$@"; }

    username=$(op read '${item}/username') || exit 1
    password=$(op read '${item}/password') || exit 1
    key=$(op read '${item}/key') || exit 1

    printf '%s\n' "$key" | timeout 120 atuin login --username "$username" --password "$password"
  '';
in
{
  home.activation.atuinLogin = lib.hm.dag.entryAfter [ "writeBoundary" ] # bash
    ''
      run ${login} \
        || warnEcho "atuin: not logged in — make sure op can reach 1Password (unlocked app on macOS, service account token on Linux) and rerun, or run 'atuin login' by hand"
    '';
}
