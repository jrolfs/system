{ lib, pkgs, config, userName, hostname, ... }:

# Linux-only home-manager shared module. Loaded automatically for every
# nixosConfiguration via home-manager.sharedModules in flake.nix.
#
# Counterpart to modules/home/darwin.nix. Provides Linux-specific
# environment tweaks; the bulk of the shell config is shared via
# modules/home/default.nix and works on both OSes.

{
  # Inert unless the host sets desktop.enable.
  imports = [ ./desktop ];

  # nix-switch and friends come from nix-commands.nix. nixos-rebuild-ng's
  # --sudo runs the build as the user and elevates only the activation; under
  # `sudo -E` the whole build ran as root with $HOME still /home/jamie, which
  # nix warns about on every invocation. Building needs no sudo at all.
  nixCommands = {
    switch = "nixos-rebuild switch --sudo";
    build = "nixos-rebuild build";
  };

  # ~/.zshrc.linux is sourced by ~/.zshrc when uname is Linux.
  # Mirrors the .zshrc.darwin pattern from darwin.nix; the existing
  # dotfiles/home/.zshrc has the platform-rc lookup that picks the
  # right file based on uname.
  home.file.".zshrc.linux".text = # zsh
    ''
      #
      #
      # Aliases ----------------------------------------------------------------------

    '';

  # Declared inline rather than lifted from the dotfiles tree because the
  # macOS copy names pinentry-mac, which doesn't exist here. Irulan is
  # headless, so curses is the only pinentry that can work.
  #
  # enable-ssh-support is not optional on this host: the shared git config
  # rewrites every github.com URL to SSH via insteadOf, and the shared .zshenv
  # points SSH_AUTH_SOCK at ~/.gnupg/S.gpg-agent.ssh — a socket gpg-agent only
  # creates when asked. Without it there is no agent and no key on disk, so
  # every fetch fails.
  home.file.".gnupg/gpg-agent.conf".text = ''
    enable-ssh-support
    pinentry-program ${pkgs.pinentry-curses}/bin/pinentry-curses
    default-cache-ttl 60480000
    max-cache-ttl 60480000
  '';

  # Linux-side packages on top of the system-wide environment.systemPackages
  # in modules/nixos/default.nix. User-installed via home-manager profile.
  home.packages = with pkgs; [
    # Currently empty — add as Linux-only personal tools surface.
  ];
}
