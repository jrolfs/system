{ config, lib, pkgs, ... }:

# opencode, set up the way Claude Code is: settings generated here, MCP servers
# shared through programs.mcp (mcp.nix), and the binary installed system-wide by
# modules/shared/packages.nix. Zed's OpenCode agent runs that same binary
# (`opencode acp`), so both read this config.
#
# Every provider authenticates with an API key, Anthropic included, so each one
# is set up the same way. Subscription logins through plugins are left out on
# purpose.
#
# Keys come from the files secrets.nix writes, through opencode's own
# `{file:…}` substitution, so a key reaches opencode and nothing else. A
# provider is listed only on hosts whose manifest entries give it a key file,
# because a `{file:…}` naming a missing file makes opencode reject its whole
# config. On adrian that means none yet: Claude there is Foundry, which
# opencode doesn't speak natively.
#
# TODO: work through what we built for Claude Code across machines, once this
# has settled, and decide what each needs here.
# - Keying: Claude files a thread under its working directory
#   (~/.claude/projects/<slug>). opencode keys a project by its repo's first
#   commit and keeps everything in one SQLite database
#   (~/.local/share/opencode/opencode.db).
# - Sync: claude-sync (claude-sync.nix, patched in overlays/claude-sync/) pushes
#   and pulls ~/.claude through B2 from SessionStart and Stop hooks. A live
#   SQLite file can't be synced like that. The likely analog is one
#   `opencode serve` on irulan that every machine attaches to.
# - Moving threads: claude-mv-project re-keys a store when its directory moves,
#   and wt-relocate runs it per worktree. Probably moot if commit keying holds
#   across worktrees.
# - Handoff: wt handoff/restore carry a worktree's dirty state between machines
#   and pull claude-sync first so its threads resume at the same path.
# - Zed: claude-zed-sync carries and moves Zed's agent-panel thread records, and
#   resume-zed / claude-zed-threads list ACP threads with resume commands.
#   Check what opencode's ACP agent keeps itself.
# - Kitty: worktree/switch.py swaps panes on `wt switch` and leaves the Claude
#   pane alone. Likely moot if threads follow the project.
# - MCP: shared below. Remote servers need opencode's own OAuth once per
#   machine (`opencode mcp auth <server>`).

let
  # opencode provider ID to the bootstrap secrets.json entry holding its key.
  # Qwen would be `alibaba` (pay-as-you-go DashScope, international endpoint)
  # once it has an entry.
  keys = {
    anthropic = "anthropic-api-key";
    openai = "openai-api-key";
  };

  available = lib.filterAttrs (_: entry: config.secrets.files ? ${entry}) keys;

  # The auto-mode review pipeline, cheapest first. Each stage either decides
  # (allow, deny or ask) or abstains to the next, and if every stage abstains
  # the action is a prompt.
  #
  # - static: fixed rules, no network. Denies known-dangerous commands and
  #   allows plain read-only ones.
  # - TypeSafe's Jev, where this host has the key: a typed decision model
  #   that answers with calibrated confidence in tens of milliseconds. Below
  #   0.9 confidence an allow abstains and a deny asks, so it only settles
  #   clear cases. It receives the pending action and the visible
  #   transcript, so it's on the personal machines only.
  # - Claude Sonnet as the reviewer of last resort, where this host has the
  #   Anthropic key: the plugin's two-pass review (quick triage, then
  #   reasoning on anything flagged) under its built-in policy, which
  #   follows Claude Code's auto mode. Pinned rather than following the
  #   session's model so the judge stays the same whichever model is doing
  #   the work. Without the key it falls back to the session's model.
  reviewers =
    [ { type = "static"; } ]
    ++ lib.optional (config.secrets.files ? typesafe-api-key) {
      type = "decision";
      model = "typesafe-ai/jev-latest";
      apiKeyFile = config.secrets.files.typesafe-api-key;
    }
    ++ [
      ({ type = "llm"; }
        // lib.optionalAttrs (available ? anthropic) { model = "anthropic/claude-sonnet-5-5"; })
    ];
in
{
  programs.opencode = {
    enable = true;

    # Installed system-wide by modules/shared/packages.nix.
    package = null;

    enableMcpIntegration = true;

    settings = {
      provider = lib.mapAttrs
        (_: entry: { options.apiKey = "{file:${config.secrets.files.${entry}}}"; })
        available;

      # Something like Claude Code's auto mode. opencode 2 allows every action
      # unless a rule says otherwise, so everything starts at `ask`, and the
      # plugin reviews each ask before it reaches a prompt: fixed checks first
      # (dangerous shell commands denied, common read-only ones allowed), then
      # the session's own model with the conversation as context. Anything it
      # can't decide, or any failure, stays a prompt.
      #
      # opencode has no model-checked mode of its own yet
      # (anomalyco/opencode#37564). The plugin is a patched build of an exact
      # release (pkgs.opencode-auto-mode in overlays/default.nix, which says
      # what the patch changes), loaded from its store path. It is young and is
      # trusted with approvals: read the changes before bumping it.
      permissions = [
        { action = "*"; resource = "*"; effect = "ask"; }
      ];

      plugins = [
        {
          package = "${pkgs.opencode-auto-mode}";
          options = {
            classifiers = reviewers;
            auditLog = true;
          };
        }
      ];
    };
  };
}
