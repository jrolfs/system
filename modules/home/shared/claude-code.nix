{ config, lib, pkgs, ... }:

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

let
  knownMarketplaces = "${config.home.homeDirectory}/.claude/plugins/known_marketplaces.json";

  # The merge into known_marketplaces.json is a deep one, so a `directory`
  # source written over the `github` entry Claude Code made for worktrunk
  # would keep that entry's `repo` key alongside the new `path`. Dropping the
  # GitHub entry first lets the declared one land clean. Safe to delete once
  # every machine has switched past this change.
  dropGitHubWorktrunk = pkgs.writeShellScript "drop-github-worktrunk-marketplace" ''
    set -eu
    [ -f "$1" ] || exit 0
    ${lib.getExe pkgs.jq} -e '.worktrunk.source.source == "github"' "$1" >/dev/null || exit 0
    ${lib.getExe pkgs.jq} 'del(.worktrunk)' "$1" > "$1.tmp"
    mv "$1.tmp" "$1"
  '';
in
{
  home.activation.claudeCodeWorktrunkMarketplace =
    lib.hm.dag.entryBetween [ "claudeCodeSettings" ] [ "linkGeneration" ] # bash
      ''
        run ${dropGitHubWorktrunk} "${knownMarketplaces}"
      '';

  programs.claude-code = {
    enable = true;

    # Installed system-wide by modules/shared/packages.nix. Null also tells the
    # module to assume a current Claude Code, so it takes the personal-plugin
    # route rather than wrapping the binary in `--plugin-dir`.
    package = null;

    mutableSettings = true;

    # From the same source as the `wt` in modules/shared/packages.nix, so the
    # plugin moves with the binary it describes instead of tracking GitHub's
    # main branch. `worktrunk@worktrunk` in enabledPlugins below turns it on.
    marketplaces.worktrunk = pkgs.worktrunk.src;

    # These replace the *-lsp plugins from claude-plugins-official, which
    # declare the same servers by bare command name and leave installing them
    # to whatever is on PATH. Two were broken that way: nothing installed
    # typescript-language-server, and rustup has no rust-analyzer for the
    # stable toolchain, so its proxy fell through to a mise shim that resolved
    # back to rustup. typescript-language-server still uses each project's own
    # node_modules/typescript; nixpkgs' typescript is the native port, which
    # has no tsserver to fall back on.
    #
    # clangd and sourcekit-lsp stay bare and macOS-only. Apple's builds know
    # the Xcode SDK, and a C or Swift project with a devshell gets that
    # toolchain's server instead.
    lspServers = {
      typescript = {
        command = "${pkgs.typescript-language-server}/bin/typescript-language-server";
        args = [ "--stdio" ];
        extensionToLanguage = {
          ".ts" = "typescript";
          ".tsx" = "typescriptreact";
          ".js" = "javascript";
          ".jsx" = "javascriptreact";
          ".mts" = "typescript";
          ".cts" = "typescript";
          ".mjs" = "javascript";
          ".cjs" = "javascript";
        };
      };

      lua = {
        command = "${pkgs.lua-language-server}/bin/lua-language-server";
        extensionToLanguage.".lua" = "lua";
      };

      rust-analyzer = {
        command = "${pkgs.rust-analyzer}/bin/rust-analyzer";
        extensionToLanguage.".rs" = "rust";
      };
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      clangd = {
        command = "clangd";
        args = [ "--background-index" ];
        extensionToLanguage = {
          ".c" = "c";
          ".h" = "c";
          ".cpp" = "cpp";
          ".cc" = "cpp";
          ".cxx" = "cpp";
          ".hpp" = "cpp";
          ".hxx" = "cpp";
          ".C" = "cpp";
          ".H" = "cpp";
        };
      };

      sourcekit-lsp = {
        command = "sourcekit-lsp";
        extensionToLanguage.".swift" = "swift";
      };
    };

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

      # Off rather than absent: the settings merge never deletes a key, so
      # dropping these would leave them enabled beside lspServers above, with
      # two servers claiming each extension.
      enabledPlugins = {
        "worktrunk@worktrunk" = true;
        "clangd-lsp@claude-plugins-official" = false;
        "swift-lsp@claude-plugins-official" = false;
        "typescript-lsp@claude-plugins-official" = false;
        "lua-lsp@claude-plugins-official" = false;
        "rust-analyzer-lsp@claude-plugins-official" = false;
      };
    };
  };
}
