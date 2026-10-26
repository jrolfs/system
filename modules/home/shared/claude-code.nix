{ pkgs, ... }:

# Claude Code's user settings, declared here and merged into
# ~/.claude/settings.json at activation rather than linked from the repo.
#
# Claude Code writes that file itself (/config, /plugin, /model), so it can't
# be a read-only store link. It used to be an out-of-store link into
# dotfiles/home, which kept every runtime write as a git diff but meant nothing
# here could generate it: setting a marketplace or a disabled MCP server would
# have made home-manager claim the same path. `mutableSettings` makes it a
# plain file instead. Each switch writes the keys declared below over whatever
# is there and leaves every other key alone, so a toggle made in a session
# lasts until it collides with a declaration, and a key removed from here has
# to be removed from the file by hand.
#
# Arrays are replaced rather than unioned, which matters for
# `permissions.allow`: a rule granted at user scope during a session is gone
# after the next switch unless it's added here. "Don't ask again" normally
# writes to the project's settings.local.json instead, so this rarely bites.

{
  programs.claude-code = {
    enable = true;

    # Installed system-wide by modules/shared/packages.nix. Null also tells the
    # module to assume a current Claude Code, so it takes the personal-plugin
    # route rather than wrapping the binary in `--plugin-dir`.
    package = null;

    mutableSettings = true;

    settings = {
      cleanupPeriodDays = 90;
      includeCoAuthoredBy = true;

      permissions = {
        allow = [
          "WebSearch"
          "WebFetch(domain:raw.githubusercontent.com)"
          "WebFetch(domain:github.com)"
          "WebFetch(domain:json.schemastore.org)"
          "WebFetch(domain:www.schemastore.org)"
          "Bash(curl:*)"
          "Bash(echo:*)"
          "Bash(ls:*)"
          "Bash(cat:*)"
          "Bash(grep:*)"
          "Bash(gh search code:*)"
          "Bash(git check-ignore:*)"
          "Bash(swift build:*)"
        ];
        defaultMode = "auto";
      };

      model = "claude-opus-5-5[1m]";
      effortLevel = "xhigh";
      tui = "default";
      autoMemoryEnabled = true;
      autoCompactEnabled = true;
      theme = "auto";
      editorMode = "vim";
      preferredNotifChannel = "kitty";

      # claude-sync's own `auto enable` would write these, by bare command
      # name. Declaring them pins both tools to this generation's builds.
      # The Stop hook stays one command because hooks for the same event run
      # in parallel, and the Zed thread export has to land before the push.
      hooks = {
        SessionStart = [
          {
            matcher = "";
            hooks = [
              {
                type = "command";
                command = "${pkgs.claude-sync}/bin/claude-sync pull -q";
              }
            ];
          }
        ];
        Stop = [
          {
            matcher = "";
            hooks = [
              {
                type = "command";
                command = "${pkgs.claude-helpers}/bin/claude-zed-sync export >/dev/null; ${pkgs.claude-sync}/bin/claude-sync push -q";
              }
            ];
          }
        ];
      };

      enabledPlugins = {
        "clangd-lsp@claude-plugins-official" = true;
        "swift-lsp@claude-plugins-official" = true;
        "worktrunk@worktrunk" = true;
        "typescript-lsp@claude-plugins-official" = true;
        "lua-lsp@claude-plugins-official" = true;
        "rust-analyzer-lsp@claude-plugins-official" = true;
      };

      extraKnownMarketplaces.worktrunk.source = {
        source = "github";
        repo = "max-sixty/worktrunk";
      };
    };
  };
}
