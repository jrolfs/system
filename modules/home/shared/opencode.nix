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
# config. On adrian that means Foundry alone, as a custom provider (below).
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

  files = config.secrets.files;

  # Microsoft Foundry, on hosts that get its key and resource (the work
  # machine), through its Anthropic-compatible endpoint. Foundry names its own
  # deployments and has no model-list endpoint, so they're declared here,
  # matching what the resource serves: Opus 5, Opus 5.5 and Haiku 4.5, with no
  # Sonnet. It takes the key as `x-api-key`, which is what `apiKey` sends, and
  # wants the `/v1` on the base URL. The resource name is a secret too, so it's
  # substituted into the URL from its file.
  foundry = files ? foundry-api-key && files ? foundry-resource;

  foundryProvider = {
    name = "Microsoft Foundry";
    canonical = "anthropic";
    package = "@opencode/ai/providers/anthropic-compatible";
    settings = {
      baseURL = "https://{file:${files.foundry-resource}}.services.ai.azure.com/anthropic/v1";
      apiKey = "{file:${files.foundry-api-key}}";
    };
    models = lib.genAttrs [ "claude-opus-5-5" "claude-opus-5" "claude-haiku-4-5" ] (id: { modelID = id; });
  };

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
  # - A Claude model as the reviewer of last resort: the plugin's two-pass
  #   review (quick triage, then reasoning on anything flagged) under its
  #   built-in policy, which follows Claude Code's auto mode. Sonnet with the
  #   personal Anthropic key, or Opus 5.5 through Foundry, which has no
  #   Sonnet. Pinned rather than following the session's model, so the judge
  #   stays the same whichever model is doing the work.
  reviewers =
    [ { type = "static"; } ]
    ++ lib.optional (config.secrets.files ? typesafe-api-key) {
      type = "decision";
      model = "typesafe-ai/jev-latest";
      apiKeyFile = config.secrets.files.typesafe-api-key;
    }
    ++ [
      ({ type = "llm"; }
        // lib.optionalAttrs (available ? anthropic) { model = "anthropic/claude-sonnet-5-5"; }
        // lib.optionalAttrs (!(available ? anthropic) && foundry) { model = "foundry/claude-opus-5-5"; })
    ];

  # Models for the memory plugin's hidden agents, from whichever provider this
  # host has: a fast one for recall (every turn) and extraction (each idle
  # session), a stronger one for the occasional consolidation pass. Left to
  # the session's model these would fail on opencode's free models, which
  # reject a request without its shell tool.
  memoryModels =
    if available ? anthropic then { fast = "anthropic/claude-haiku-4-5"; strong = "anthropic/claude-sonnet-5-5"; }
    else if foundry then { fast = "foundry/claude-haiku-4-5"; strong = "foundry/claude-opus-5-5"; }
    else null;
in
{
  programs.opencode = {
    enable = true;

    # Installed system-wide by modules/shared/packages.nix.
    package = null;

    enableMcpIntegration = true;

    # The terminal client's settings, cli.json in opencode 2 (tui.json was the
    # old client's). The `system` theme takes the terminal's own colors.
    cli.theme.name = "system";

    settings = {
      providers = lib.mapAttrs (_: entry: { settings.apiKey = "{file:${files.${entry}}}"; }) available
        // lib.optionalAttrs foundry { foundry = foundryProvider; };
    } // lib.optionalAttrs (foundry && available == { }) {
      # Where Foundry is the only provider, start sessions on it rather than
      # on whatever opencode would pick from its free tier.
      model = "foundry/claude-opus-5-5";
      small_model = "foundry/claude-haiku-4-5";
    } // {

      # Claude Code's instructions, which opencode 2 no longer reads by itself
      # (it looks for AGENTS.md only). A relative entry is matched upwards from
      # the session's directory to the project root, whichever config declares
      # it, so this one line picks up every CLAUDE.md on the way, nested ones
      # included, the way Claude Code does. A repo with both files gets both.
      instructions = [
        "CLAUDE.md"
        "${config.home.homeDirectory}/.claude/CLAUDE.md"
      ];

      # Skills under ~/.claude/skills and a project's .claude/skills are read
      # natively. Skills that arrive inside Claude Code plugins are not, so
      # worktrunk's comes from its package instead. Not wt-switch-create, which
      # drives Claude Code's EnterWorktree tool.
      skills = [ "${pkgs.worktrunk}/share/skills/worktrunk/worktrunk" ];

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
      #
      # The last matching rule wins, so the memory plugin's tools, which only
      # touch its memory folder, run without a review.
      permissions = [
        { action = "*"; resource = "*"; effect = "ask"; }
        { action = "memory_*"; resource = "*"; effect = "allow"; }
      ];

      plugins = [
        {
          package = "${pkgs.opencode-auto-mode}";
          options = {
            classifiers = reviewers;
            auditLog = true;
          };
        }

        # Claude Code's memory, shared: opencode reads and writes the same
        # ~/.claude/projects/<project>/memory/ folder, in the same format, so
        # either tool picks up what the other saved. It recalls relevant
        # memories before each turn and saves new ones once a session goes
        # idle, through the hidden agents configured below. claude-sync
        # carries the folder between machines as it already does. Pinned to
        # an exact release, loaded from npm.
        { package = "opencode-claude-memory@2.2.1"; }
      ];
    } // lib.optionalAttrs (memoryModels != null) {
      agents = {
        opencode-memory-recall.model = memoryModels.fast;
        opencode-memory-extract.model = memoryModels.fast;
        opencode-memory-dream.model = memoryModels.strong;
      };
    };
  };
}
