{ pkgs, ... }:

# Packages every machine gets, whatever it runs.
#
# `environment.systemPackages` is spelled the same in nix-darwin and NixOS, so
# one module serves both and there is a single place to add a tool. Before this
# existed the NixOS list was a hand-maintained subset of the darwin one — which
# meant the answer to "why isn't `rg` on the NUC" was that nobody had copied the
# line across yet, and the two drifted every time either changed.
#
# What stays out: anything that only means something on one platform (see the
# lists in modules/darwin and modules/nixos), and anything heavy enough that a
# host should opt into it rather than receive it by default.

{
  environment.systemPackages = [

    #
    # Utilities

    # Shell

    pkgs.atuin
    pkgs.bat
    pkgs.bottom
    pkgs.eza
    pkgs.fd
    pkgs.jq
    pkgs.miller
    pkgs.ripgrep
    pkgs.sd
    pkgs.skim
    pkgs.starship
    pkgs.tealdeer
    pkgs.tmux
    pkgs.yq
    pkgs.zoxide
    pkgs.zsh

    # Network

    pkgs.rclone
    pkgs.wakeonlan

    #
    # Build

    pkgs.autoconf
    pkgs.automake
    pkgs.cmake

    #
    # Fun

    pkgs.fortune
    pkgs.figlet
    pkgs.dotacat

    #
    # Media

    pkgs.ffmpeg
    pkgs.imagemagick
    pkgs.yt-dlp

    #
    # Git

    pkgs.delta
    pkgs.gh
    pkgs.git
    pkgs.git-crypt
    pkgs.git-lfs
    pkgs.worktrunk

    #
    # Security

    # pinentry-curses rather than the platform's GUI prompt: it's the only one
    # that works over SSH, and a headless host has nowhere to put a window.
    # Darwin adds pinentry_mac alongside it.
    pkgs.gnupg
    pkgs.pinentry-curses
    pkgs.yubikey-manager

    #
    # Development tools

    pkgs.httpie
    pkgs.mise

    # Language servers
    pkgs.lua-language-server
    pkgs.nixd
    pkgs.yaml-language-server
    pkgs.zshcs

    #
    # Editors

    pkgs.neovim
    pkgs.nil
    pkgs.tree-sitter

    # Nix
    pkgs.nixpkgs-fmt

    #
    # AI

    pkgs.claude-code
    pkgs.claude-monitor
    pkgs.claude-code-router

    pkgs.opencode
    pkgs.opencode-claude-auth

    pkgs.mcp-nixos

  ];
}
