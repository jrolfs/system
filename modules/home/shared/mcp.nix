{ config, lib, pkgs, ... }:

# MCP servers available in every session on every machine, declared once in
# programs.mcp.servers and handed to each harness through home-manager's own
# `enableMcpIntegration` switch. Adding a harness later is a matter of flipping
# that switch on its module, not of restating the servers.
#
# Claude Code keeps user-scope servers in ~/.claude.json, a mutable blob of
# history, cached auth and per-project state that can't be linked from the
# repo, which is why this used to be a manifest plus a `claude mcp add-json`
# sync script run by hand. home-manager sidesteps that file: it builds a plugin
# carrying the servers in its .mcp.json and links it under ~/.claude/skills/,
# where Claude Code loads personal plugins from. The cost is the tool prefix,
# which becomes `mcp__plugin_hm_<server>__` rather than `mcp__<server>__`, so
# any permission rule naming an MCP tool has to use the longer form.
#
# OAuth tokens are not part of any of this. Claude Code caches them per
# machine after a one-time `/mcp` login, which is where they belong.
#
# opencode takes the same servers through opencode.nix. Zed has an integration
# too, and it's off for now rather than forgotten. home-manager would generate
# Zed's settings.json, which is an out-of-store link because Zed writes it
# back, so turning it on means handing that file over first.

let
  # GitHub's hosted server, api.githubcopilot.com/mcp, has no dynamic client
  # registration, so `/mcp` can't sign in to it the way it does the URLs below.
  # It would need an OAuth app registered by hand, which an org restricting
  # third-party access then has to approve, or a token written into a header.
  # The local server borrows the token `gh auth login` already holds instead,
  # read at launch so it never reaches the store, and so it sees every org gh
  # does. On a machine where gh isn't logged in, the server just fails to start.
  github = pkgs.writeShellScript "github-mcp-server" ''
    GITHUB_PERSONAL_ACCESS_TOKEN=$(${lib.getExe config.programs.gh.package} auth token) || exit
    export GITHUB_PERSONAL_ACCESS_TOKEN
    exec ${lib.getExe pkgs.github-mcp-server} stdio
  '';
in
{
  programs.mcp = {
    enable = true;

    # `enabled = false` on a server leaves it out entirely instead of passing it
    # through. home-manager's own handling of that flag adds the server to
    # `disabledMcpjsonServers` in ~/.claude/settings.json, which doesn't hide a
    # server that arrives through a plugin, as these do.
    servers = lib.filterAttrs (_: server: server.enabled or null != false) {
      airtable.url = "https://mcp.airtable.com/mcp";
      figma.url = "https://mcp.figma.com/mcp";
      granola.url = "https://mcp.granola.ai/mcp";
      linear.url = "https://mcp.linear.app/mcp";
      ramp.url = "https://mcp.ramp.com/mcp";
      sentry.url = "https://mcp.sentry.dev/mcp";
      superhuman.url = "https://mcp.mail.superhuman.com/mcp";

      # Home Assistant's mcp_server integration, whose config entry is made in
      # its UI. It has no dynamic client registration either, but it accepts a
      # Client ID Metadata Document, which Claude Code and opencode both send,
      # so `/mcp` signs in to it like the URLs above. That depends on
      # home.rolfs.casa being Home Assistant's external_url, which the
      # home-assistant module sets. Otherwise its OAuth metadata has relative
      # endpoints and no issuer, and clients reject it.
      #
      # /api/mcp serves the LLM APIs chosen in the integration's options and,
      # unless they say otherwise, only to an admin. /api/mcp/assist serves
      # Assist alone, which reaches only the entities exposed to voice
      # assistants, to any user.
      home-assistant.url = "https://home.rolfs.casa/api/mcp";
      home-assistant-assist.url = "https://home.rolfs.casa/api/mcp/assist";

      # By store path rather than from PATH, so the server is the one this
      # generation built and nothing else has to install it.
      nixos.command = "${pkgs.mcp-nixos}/bin/mcp-nixos";
      github.command = "${github}";
    };
  };

  programs.claude-code.enableMcpIntegration = true;
}
