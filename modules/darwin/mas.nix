{ config, lib, pkgs, hostname, ... }:

# Mac App Store apps, installed by driving `mas` directly rather than through
# `brew bundle`'s mas integration. The App Store has nothing to do with
# Homebrew, and routing it through bundle ties these installs to the health of
# the Homebrew stack — zhaofengli/nix-homebrew#131 is exactly that coupling
# failing, with mas installs breaking on a nix-homebrew bump.
#
# Deliberately not nix-darwin's own `programs.mas` module, despite it being the
# obvious home for this. Its activation script runs a bare `exit 0` when
# `mas list` reports "not signed in", and that text is interpolated straight
# into the single `activate` script — so it exits *activation*, skipping the
# Homebrew section that follows it and postActivation after that, while still
# returning success. A machine that has never had the App Store signed into is
# signed out by default, which makes that the normal first-switch path rather
# than a corner: bootstrap would record `first-switch-completed` against a
# system where `brew bundle` never ran. Running our own script as a separate
# process contains any exit to that process.
#
# `mas install` can only fetch apps already in the signed-in account's purchase
# history. That was equally true through `brew bundle`, so nothing is lost.

let
  excludeApps = (import ./excluded-apps.nix).${hostname} or [ ];

  apps = lib.filterAttrs (name: _: !lib.elem name excludeApps) {
    "Cloud Baby Monitor" = 517602535;
    "Fantastical" = 975937182;
    "Flighty" = 1358823008;
    "Velja" = 1607635845;
    "Xcode" = 497799835;
  };

  # No stamp guarding this the way the Homebrew gate is guarded: `mas list` is
  # a local query that returns in well under a tenth of a second, and running
  # it every switch is what reinstates an app that was removed by hand.
  #
  # Upgrades are left to the App Store itself. `mas upgrade` would mean an
  # unbounded download inside every switch, which is the cost the Homebrew gate
  # exists to avoid paying.
  install = pkgs.writeShellScript "mas-install" ''
    set -uo pipefail

    export PATH=${lib.makeBinPath [ pkgs.mas pkgs.gnugrep pkgs.coreutils ]}:$PATH

    if ! installed=$(mas list 2>&1); then
      echo "mas: could not list App Store apps, skipping" >&2
      printf '%s\n' "$installed" >&2
      exit 0
    fi

    status=0

    # `mas list` prints "<id>  <name>  (<version>)", right-aligned, hence the
    # leading whitespace in the match.
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: id: ''
      if ! printf '%s\n' "$installed" | grep -q '^ *${toString id} '; then
        echo "mas: installing ${name} (${toString id})" >&2
        mas install ${toString id} || status=1
      fi
    '') apps)}

    exit $status
  '';
in
{
  environment.systemPackages = [ pkgs.mas ];

  system.activationScripts.mas.text = lib.mkIf (apps != { }) ''
    echo >&2 "App Store apps..."
    sudo --user=${config.system.primaryUser} --set-home ${install} \
      || echo >&2 "warning: mas: some App Store apps could not be installed"
  '';
}
