{ config, lib, pkgs, ... }:

# Which account Claude Code bills, by host. Plain `claude` and Zed's registry
# claude-acp sign in with the subscription. The variants here set credentials
# for their own process only, read from the files secrets.nix writes, so no key
# sits in the shell environment for every other command to inherit.
#
# - `claude-api` / `claude-api-acp`: the personal Anthropic API key. Opt-in,
#   on any host that gets `anthropic-api-key`.
# - Foundry, on hosts that get `foundry-api-key` and `foundry-resource` (the
#   work machine): `claude` itself is replaced, since there it should always
#   be Foundry, and `claude-foundry-acp` is the Zed agent.
#
# Each variant clears the other's variables, so one leaking in from an old
# shell can't redirect it. The `-acp` wrappers are what Zed's agent_servers
# entries run, by their /etc/profiles/per-user path.

let
  files = config.secrets.files;

  claude = "${pkgs.claude-code}/bin/claude";
  acp = lib.getExe pkgs.claude-agent-acp;

  foundryVariables = [ "CLAUDE_CODE_USE_FOUNDRY" "ANTHROPIC_FOUNDRY_RESOURCE" "ANTHROPIC_FOUNDRY_API_KEY" ];

  # `variables` maps a variable to the secret entry whose file holds its value,
  # or to a literal under `value`.
  wrapper = { name, command, variables, unset }:
    pkgs.writeShellScriptBin name ''
      set -eu
      ${lib.concatStrings (lib.mapAttrsToList (variable: source:
        if source ? value then ''
          export ${variable}=${lib.escapeShellArg source.value}
        '' else ''
          ${variable}=$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg files.${source.file}})
          export ${variable}
        '') variables)}
      unset ${lib.concatStringsSep " " unset}
      exec ${command} "$@"
    '';

  anthropic = files ? anthropic-api-key;
  foundry = files ? foundry-api-key && files ? foundry-resource;

  apiEnvironment = { ANTHROPIC_API_KEY.file = "anthropic-api-key"; };

  foundryEnvironment = {
    CLAUDE_CODE_USE_FOUNDRY.value = "1";
    ANTHROPIC_FOUNDRY_RESOURCE.file = "foundry-resource";
    ANTHROPIC_FOUNDRY_API_KEY.file = "foundry-api-key";
  };
in
{
  home.packages =
    lib.optionals anthropic [
      (wrapper { name = "claude-api"; command = claude; variables = apiEnvironment; unset = foundryVariables; })
      (wrapper { name = "claude-api-acp"; command = acp; variables = apiEnvironment; unset = foundryVariables; })
    ]
    ++ lib.optionals foundry [
      # Ahead of the system-wide claude on PATH, since per-user profiles come
      # first.
      (wrapper { name = "claude"; command = claude; variables = foundryEnvironment; unset = [ "ANTHROPIC_API_KEY" ]; })
      (wrapper { name = "claude-foundry-acp"; command = acp; variables = foundryEnvironment; unset = [ "ANTHROPIC_API_KEY" ]; })
    ];
}
