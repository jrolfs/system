{ pkgs, lib, config, ... }:

# Syncs Claude Code session state between machines through a Backblaze B2
# bucket (S3-compatible endpoint), end-to-end encrypted with age. Scope is
# "sessions": projects/, history.jsonl, tasks/, plans/. Settings, agents, and
# skills are deliberately excluded because this repo manages them; syncing
# them too would fight the flake.
#
# claude-sync reads credentials only from ~/.claude-sync/config.yaml (no env
# var support), and the age identity must be byte-identical on every machine
# and is unrecoverable if lost. Both therefore come from one 1Password item
# (op://Secrets/Claude Sync) at activation, same shape as the atuin login:
# guarded on the files already existing, so the op authorization prompt
# happens once per machine, and a switch with 1Password locked degrades to a
# warning. The bucket/endpoint/region live in the same item rather than here
# so provisioning a machine needs no repo edit when the bucket changes.
#
# Sync automation is claude-sync's own Claude Code hooks (SessionStart pulls,
# Stop pushes): `claude-sync auto enable` writes them into ~/.claude/
# settings.json, which stays under dotfile management rather than being
# mutated here.

let
  item = "op://Secrets/Claude Sync";
  configDirectory = "${config.home.homeDirectory}/.claude-sync";

  setup = pkgs.writeShellScript "claude-sync-setup" ''
    set -uo pipefail

    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}:$PATH

    [ -e ${configDirectory}/config.yaml ] && [ -e ${configDirectory}/age-key.txt ] && exit 0

    op() { timeout 120 /opt/homebrew/bin/op --account rolfers.1password.com "$@"; }

    mkdir -p ${configDirectory}
    chmod 700 ${configDirectory}
    umask 177

    if [ ! -e ${configDirectory}/age-key.txt ]; then
      key=$(op read '${item}/age-key') || exit 1
      printf '%s\n' "$key" > ${configDirectory}/age-key.txt
    fi

    if [ ! -e ${configDirectory}/config.yaml ]; then
      bucket=$(op read '${item}/bucket') || exit 1
      endpoint=$(op read '${item}/endpoint') || exit 1
      accessKey=$(op read '${item}/access-key-id') || exit 1
      secretKey=$(op read '${item}/secret-access-key') || exit 1

      # claude-sync validates region as required for S3 (its endpoint-derived
      # region is a wizard convenience, not a load-time default), but a B2
      # endpoint always embeds it: s3.<region>.backblazeb2.com.
      region=$(printf '%s' "$endpoint" | sed -E 's|^https?://||' | cut -d. -f2)

      cat > ${configDirectory}/config.yaml <<CONFIG
    storage:
      provider: s3
      bucket: $bucket
      access_key_id: $accessKey
      secret_access_key: $secretKey
      endpoint: $endpoint
      region: $region
    encryption_key_path: ~/.claude-sync/age-key.txt
    scope: sessions
    CONFIG
    fi
  '';
in
{
  home.packages = [ pkgs.claude-sync ];

  home.activation.claudeSync = lib.hm.dag.entryAfter [ "writeBoundary" ] # bash
    ''
      run ${setup} \
        || warnEcho "claude-sync: not configured — fill in the 1Password item (Secrets → Claude Sync), unlock 1Password, and rerun"
    '';
}
