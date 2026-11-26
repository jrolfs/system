{ pkgs, lib, ... }:

# What home-manager does when an unmanaged file is sitting where one of its
# links belongs. Without this, activation aborts the whole switch — which is
# exactly what happens on a fresh machine, since bootstrap links the private
# homeshick castle before the first switch and apps like spicetify regenerate
# their config dirs on first launch.
#
# `backupFileExtension` would leave a trail of `.hm-backup` files scattered
# through $HOME. This collects them into one tree instead, mirroring their
# original paths, so the whole pile can be reviewed and then removed with a
# single `rm -rf`.

let
  root = ".home-manager-backups";

  # home-manager passes the absolute path of the offending file as the only
  # argument, so the path relative to $HOME — the part worth reproducing under
  # the backup root — has to be recovered by stripping the prefix.
  command = pkgs.writeShellScript "home-manager-backup" ''
    set -euo pipefail

    PATH=${lib.makeBinPath [ pkgs.coreutils ]}:$PATH

    target="$1"
    [ -e "$target" ] || exit 0

    relative="''${target#"$HOME"/}"
    destination="$HOME/${root}/$relative"

    # A later switch can collide with the same path again; suffix rather than
    # overwrite so the first backup is never the one that gets destroyed.
    if [ -e "$destination" ]; then
      destination="$destination.$(date +%Y%m%d%H%M%S)"
    fi

    mkdir -p "$(dirname "$destination")"
    mv "$target" "$destination"

    echo "backed up $target -> $destination" >&2
  '';
in
{
  home-manager.backupCommand = "${command}";
}
