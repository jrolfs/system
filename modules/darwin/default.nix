{ pkgs, inputs, userName, ... }:

let
  overlays = import ../../overlays inputs;

in
{
  users.users.${userName}.home = "/Users/${userName}";

  imports = [

    ../bootstrap.nix
    ../home-backup.nix
    ../packages.nix

    ./daemons.nix
    ./default-browser.nix
    ./display-profiles.nix
    ./defaults.nix
    ./fileicon.nix
    ./finder-sidebar.nix
    ./homebrew.nix
    ./glide-developer.nix
    ./icons.nix
    ./kaset.nix
    ./login-items.nix
    ./mas.nix
    ./sidecar.nix
    ./spicetify.nix
    ./spotlight.nix
    ./tailscale.nix
    ./tap.nix
    ./velja

    # ./applications/codium.nix
  ];

  # Packages
  #
  # The cross-platform ones live in ../packages.nix, imported above. What's
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
    # Infrastructure
    #
    # Work tooling. Shareable in principle — azure-cli alone is most of a
    # gigabyte, so a host opts in rather than inheriting it.

    pkgs.azure-cli
    pkgs.kubectl
    pkgs.kubectx

    #
    # Editors

    # A GUI neovim, so it wants a graphical session to be worth installing.
    pkgs.neovide

    #
    # Nix

    # devbox is on the way out (it's why nix.package is pinned to Lix 2.94),
    # and nothing uses devenv yet — neither belongs in a shared baseline while
    # that's true.
    pkgs.devbox
    pkgs.devenv

  ];

  system.activationScripts.applications.enable = true;
  system.primaryUser = "jamie";

  nixpkgs.config = {
    allowBroken = true;
    allowUnfree = true;
    allowUnsupportedSystem = true;
  };

  nixpkgs.overlays = [ overlays ];

  system.stateVersion = 5;

  services.postgresql = {
    enable = false;
    enableTCPIP = true;
  };
  services.skhd.enable = false;

  security.pam.services.sudo_local.touchIdAuth = true;

  # Pinned to 2.94.2: Lix 2.95 ("Kakigōri", 2026-03-25) removed `builtins.fetchClosure`
  # along with CA derivations, and devbox's install path depends on fetchClosure to pull
  # pinned packages from cache.nixos.org (it fails with "attribute 'fetchClosure' missing").
  # 2.94 is the last Lix that ships it. Revert to `pkgs.lix` once devbox repos move to devenv.
  nix.package = pkgs.lixPackageSets.lix_2_94.lix;
  nix.enable = true;

  nix.extraOptions = "experimental-features = nix-command flakes";

  # Flake-based registry pin. Makes `nix shell nixpkgs#foo` and
  # `nix-shell -p foo` both resolve to the flake-pinned nixpkgs.
  nix.registry.nixpkgs.flake = inputs.nixpkgs;
  nix.registry.nix-darwin.flake = inputs.nix-darwin;
  nix.nixPath = [
    "nixpkgs=${inputs.nixpkgs}"
    "nix-darwin=${inputs.nix-darwin}"
  ];

  programs.ssh.knownHosts = {
    "github.com/rsa" = {
      hostNames = [ "github.com" ];
      publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=";
    };
    "github.com/ecdsa" = {
      hostNames = [ "github.com" ];
      publicKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=";
    };
    "github.com/ed25519" = {
      hostNames = [ "github.com" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = false;
    interactiveShellInit = # zsh
      ''

        HISTFILE=$HOME/.zhistory

      '';
  };
}
