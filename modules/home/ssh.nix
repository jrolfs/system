{ pkgs, lib, ... }:

# Who is allowed to connect *in*. The outbound direction needs nothing here —
# bootstrap imports the GPG key from 1Password and gpg-agent serves it over
# SSH_AUTH_SOCK — and since that same key is the only identity that should ever
# reach these machines, authorized_keys is derived from it on the machine
# rather than distributed to it. Nothing secret is committed and there is no
# per-host key to collect.
#
# The file is written rather than symlinked because sshd's StrictModes check
# walks the resolved path, and /nix/store is group-writable: a store symlink
# here would be silently refused. (The same check rules out an
# AuthorizedKeysCommand pointing into the store, which would otherwise avoid
# needing a file at all.)
#
# This owns the file outright, so a key added by hand will be replaced on the
# next switch.
#
# On a machine being provisioned the first switch is a no-op: `gpg` and
# ~/.gnupg are both outputs of that switch, so bootstrap can only import the
# key afterwards, and there is nothing to export while activation is running.
# The file appears on the next switch instead. That's deliberate rather than a
# gap to paper over — inbound SSH isn't needed during bootstrap, and running
# on every activation is what keeps the file true afterwards.

let
  authorizedKeys = pkgs.writeShellScript "install-authorized-keys" ''
    set -uo pipefail

    PATH=${lib.makeBinPath [ pkgs.gnupg pkgs.coreutils pkgs.gawk ]}:$PATH

    # Which key, without a second place to keep that answer in sync: the same
    # gpg.conf the rest of the config already ships.
    key=$(awk '/^default-key/ { print $2; exit }' "$HOME/.gnupg/gpg.conf" 2>/dev/null)

    if [ -z "$key" ]; then
      echo "ssh: no default-key in ~/.gnupg/gpg.conf, leaving authorized_keys alone" >&2
      exit 0
    fi

    if ! exported=$(gpg --export-ssh-key "$key" 2>/dev/null); then
      echo "ssh: gpg key $key not imported yet, leaving authorized_keys alone" >&2
      exit 0
    fi

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    # Written to one side and moved into place so an interrupted activation
    # can't leave a truncated file, which would lock every key out at once.
    printf '%s\n' "$exported" > "$HOME/.ssh/authorized_keys.next"
    chmod 600 "$HOME/.ssh/authorized_keys.next"
    mv "$HOME/.ssh/authorized_keys.next" "$HOME/.ssh/authorized_keys"
  '';
in
{
  home.activation.authorizedKeys = lib.hm.dag.entryAfter [ "writeBoundary" ] # bash
    ''
      run ${authorizedKeys} \
        || warnEcho "ssh: could not write authorized_keys"
    '';
}
