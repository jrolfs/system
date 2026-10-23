{ pkgs, lib, inputs, userName, ... }:

{
  users.users.${userName}.home = "/Users/${userName}";

  imports = [

    ../shared

    ./accessibility.nix
    ./daemons.nix
    ./default-browser.nix
    ./display-profiles.nix
    ./defaults.nix
    ./fileicon.nix
    ./finder-sidebar.nix
    ./fda.nix
    ./folder-icons.nix
    ./homebrew.nix
    ./glide-developer.nix
    ./icons.nix
    ./kaset.nix
    ./login-items.nix
    ./startup.nix
    ./mas.nix
    ./sidecar.nix
    ./spicetify.nix
    ./spotlight.nix
    ./tailscale.nix
    ./tap.nix
    ./user-picture.nix
    ./velja

    # ./applications/codium.nix
  ];

  # Packages
  #
  # The cross-platform ones live in ../shared/packages.nix, imported above. What's
  # left is either macOS-only, or not yet wanted on a host that isn't a
  # workstation.

  environment.systemPackages = [

    #
    # macOS

    pkgs.m-cli
    pkgs.mackup
    pkgs.nightlight
    pkgs.terminal-notifier

    # Theming — driven by ./spicetify.nix, which is darwin-only.
    pkgs.spicetify-cli

    # GUI pinentry. The shared list carries the curses one, which is what
    # actually answers over SSH.
    pkgs.pinentry_mac

    #
    # Nix

    # Not macOS-specific, but it is why nix.package is pinned to Lix 2.94
    # below, and irulan already runs 2.95. Pinning there too would downgrade a
    # daemon that has been running against that store, for a tool on its way
    # out in favour of devenv, which is shared.
    pkgs.devbox

  ];

  system.activationScripts.applications.enable = true;
  system.primaryUser = "jamie";

  # Hands back anything root left in the user's nix cache. nix-switch ran
  # darwin-rebuild under `sudo -E`, which kept this user's HOME, so root's
  # evaluation cache landed in ~/.cache/nix owned by root, and evaluating as the
  # user afterwards failed with "attempt to write a readonly database". The
  # switch uses `sudo -H` now, but a machine's first switch past that change
  # still runs the old command, so this repairs it rather than leaving a manual
  # chown to remember on each one. Cheap enough to keep: one `find` over a
  # directory that is normally already clean.
  system.activationScripts.postActivation.text = lib.mkAfter # bash
    ''
      if [ -d /Users/${userName}/.cache/nix ]; then
        find /Users/${userName}/.cache/nix -user root -exec chown ${userName}:staff {} +
      fi
    '';

  system.stateVersion = 5;

  services.postgresql = {
    enable = false;
    enableTCPIP = true;
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  # Pinned to 2.94.2: Lix 2.95 ("Kakigōri", 2026-03-25) removed `builtins.fetchClosure`
  # along with CA derivations, and devbox's install path depends on fetchClosure to pull
  # pinned packages from cache.nixos.org (it fails with "attribute 'fetchClosure' missing").
  # 2.94 is the last Lix that ships it. Revert to `pkgs.lix` once devbox repos move to devenv.
  nix.package = pkgs.lixPackageSets.lix_2_94.lix;
  nix.enable = true;

  # The nixpkgs entries are in ../shared/nix.nix; nix-darwin is the extra here.
  nix.registry.nix-darwin.flake = inputs.nix-darwin;
  nix.nixPath = [ "nix-darwin=${inputs.nix-darwin}" ];

  # Same schedule and retention as the NixOS hosts, in nix-darwin's spelling:
  # a launchd interval rather than a systemd calendar, and nix.optimise rather
  # than auto-optimise-store, which nix-darwin advises against because it
  # hard-links during every build on APFS.
  nix.gc = {
    automatic = true;
    interval = { Weekday = 0; Hour = 3; Minute = 15; };
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;

  programs.zsh = {
    enable = true;
    enableCompletion = false;
    interactiveShellInit = # zsh
      ''

        HISTFILE=$HOME/.zhistory

      '';
  };
}
