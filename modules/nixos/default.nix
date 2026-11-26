{ pkgs, lib, inputs, userName, ... }:

# Shared NixOS configuration. Imported by every nixosConfiguration via
# flake.nix's mkNixos. Host-specific bits live in hosts/<hostname>/.

let
  overlays = import ../../overlays inputs;
in
{
  imports = [ ../bootstrap.nix ../home-backup.nix ../packages.nix ];

  # Same overlay the darwin side applies. Not darwin-specific: modules/home is
  # shared by both platforms and reaches for overlay packages unconditionally
  # (claude-helpers, zshcs), so without this a NixOS host doesn't evaluate at
  # all. Packages in it that only make sense on macOS are lazy — nothing builds
  # unless something references it.
  nixpkgs.overlays = [ overlays ];

  system.stateVersion = "24.05";

  # Nix daemon settings — keep parity with the darwin module so
  # `nix shell nixpkgs#foo` and `nix-shell -p foo` resolve the same way
  # across mac and linux hosts.
  nix.package = pkgs.lix;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  nix.registry.nixpkgs.flake = inputs.nixpkgs;
  nix.nixPath = [
    "nixpkgs=${inputs.nixpkgs}"
  ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowBroken = true;

  # Default user shell across NixOS hosts. Matches the darwin side so
  # the lifted-and-shifted .zshrc / .zshenv work without a chsh dance.
  programs.zsh.enable = true;

  # Every secret this config knows about comes from 1Password, so `op` has to
  # exist before bootstrap can materialize anything — and on NixOS there is no
  # installer step to fall back on, which is why this is declared rather than
  # left to the provisioning run.
  #
  # The module rather than a bare package: it installs a setuid wrapper the
  # desktop app's CLI integration needs, which `environment.systemPackages`
  # alone would not provide.
  programs._1password.enable = true;

  # The desktop app is what lets `op` authenticate the same way it does on
  # macOS, with the app as the authentication boundary and nothing at rest.
  # It only works where there's a graphical session, so a host that is
  # sometimes headless also keeps a service-account token — see
  # src/onepassword.ts in the bootstrap repo for how the two coexist.
  #
  # polkitPolicyOwners is not optional: without it the app cannot authorize
  # against the system's authentication agent, and the CLI integration toggle
  # silently fails to take.
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ userName ];
  };

  # Time + locale defaults. Override per host if needed.
  time.timeZone = lib.mkDefault "America/Los_Angeles";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

  # Console / terminal defaults — Linux equivalents of the macOS keyboard
  # behavior tweaks. Override in host file if it has a different layout.
  console.keyMap = lib.mkDefault "us";

  # NFS client support for the QNAP media mount declared at the host level.
  services.rpcbind.enable = true;
  boot.supportedFilesystems = [ "nfs" ];

  # The cross-platform baseline is ../packages.nix, imported above. These are
  # the ones that only make sense here: GNU coreutils is what a Linux system
  # already assumes, and adding it on darwin would shadow the BSD tools the
  # rest of that config is written against.
  environment.systemPackages = with pkgs; [
    coreutils
    curl
    htop
    wget
  ];
}
