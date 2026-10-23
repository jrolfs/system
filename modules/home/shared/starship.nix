{ ... }:

# The prompt. Settings are read from dotfiles/home/.config/starship.toml, so that
# stays the file to edit; home-manager writes ~/.config/starship.toml from it.
# The custom modules it names still live in ~/.config/starship, linked by
# default.nix.
#
# Zsh integration stays off. .zshrc runs `starship init` itself, behind the
# check in .config/zsh/starship.zsh that skips it in repositories marked slow,
# and home-manager's zsh integration would be inert anyway while .zshrc is a
# lifted file.
{
  programs.starship = {
    enable = true;
    enableZshIntegration = false;
    settings = builtins.fromTOML (builtins.readFile ../../../dotfiles/home/.config/starship.toml);
  };
}
