{ pkgs, ... }:

# `ls` in interactive zsh, through eza (dotfiles/home/.config/zsh/init/aliases.zsh).
# A package rather than a linked script so its interpreter comes from nix:
# the old `#!/bin/bash` doesn't exist on NixOS, and there every ls in every
# shell was "no such file or directory". writeShellApplication also runs
# shellcheck at build time and puts eza and git on the script's PATH, so it
# no longer depends on what the calling shell has. Its completion is ls's own,
# in dotfiles/home/.config/zsh/completions/_eza-ls.

{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "eza-ls";
      runtimeInputs = [ pkgs.eza pkgs.git ];
      text = builtins.readFile ./eza-ls.bash;
    })
  ];
}
