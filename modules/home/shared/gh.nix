{ ... }:

# The GitHub CLI's settings. hosts.yml, where `gh auth login` keeps the token,
# is left to gh: nothing sets programs.gh.hosts.
#
# The credential helper stays off. dotfiles/home/.config/git/config already
# routes github.com through `gh auth git-credential`, by the absolute path
# /etc/profiles/per-user/jamie/bin/gh: an absolute path because git run from a
# GUI app may not have this profile on PATH, and this one because
# home-manager.useUserPackages puts what this module installs there on both
# platforms.
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
