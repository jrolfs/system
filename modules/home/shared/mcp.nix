{ lib, pkgs, ... }:

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

      # By store path rather than from PATH, so the server is the one this
      # generation built and nothing else has to install it.
      nixos.command = "${pkgs.mcp-nixos}/bin/mcp-nixos";
    };
  };

  programs.claude-code.enableMcpIntegration = true;
}
