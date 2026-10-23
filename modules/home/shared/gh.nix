{ ... }:

# The GitHub CLI's settings. hosts.yml, where `gh auth login` keeps the token,
# is left to gh: nothing sets programs.gh.hosts.
#
# The credential helper stays off. dotfiles/home/.config/git/config already
# routes github.com through `gh auth git-credential`, by the absolute path
# /run/current-system/sw/bin/gh, which is why gh also stays in the system
# packages (modules/shared/packages.nix) even though this installs it too.
# Same store path, so the two copies are one.
{
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = false;

    settings = {
      version = "1";
      git_protocol = "ssh";
      aliases.co = "pr checkout";
    };
  };
}
