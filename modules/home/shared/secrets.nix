{ config, lib, pkgs, inputs, hostname, ... }:

# Writes this host's secret files from 1Password on every switch, for the
# entries in bootstrap's secrets.json that have a `target`. The manifest stays
# the one list of secrets: `bootstrap secrets add` records an entry,
# `bootstrap secrets materialize` writes it on a new machine, and this keeps
# every machine that switches in step without a bootstrap run. Reading it from
# the flake input means a new entry needs `nix flake update bootstrap` first.
#
# Only files that are missing or empty are written, which is also how bootstrap
# decides a secret still needs materializing. So 1Password is asked once per
# file per machine, and a switch with it locked degrades to a warning, the same
# as atuin.nix and claude-sync.nix. Rotating a secret is deleting its file and
# switching, or `bootstrap secrets materialize <name>`.
#
# Files on disk are the stopgap documentation/SECRETS.md ranks last. Several
# consumers start outside any shell (Zed launching an agent, opencode resolving
# `{file:…}`), and `op read` at each launch would mean a Touch ID prompt
# whenever Zed starts one. Replacing this with something that keeps nothing at
# rest, a hardware key or an agent, changes this module and not its consumers.

let
  manifest = lib.importJSON "${inputs.bootstrap}/secrets.json";
  home = config.home.homeDirectory;

  # Defaults as in bootstrap's schema (src/schemas.ts).
  applies = entry:
    let hosts = entry.hosts or [ "*" ]; in
    builtins.elem "*" hosts || builtins.elem hostname hosts;

  entries = lib.filterAttrs (_: entry: entry ? target && applies entry) manifest.secrets;

  # bootstrap also accepts a short `Item/field` reference resolved against its
  # configured vault. Nothing with a target uses one, and resolving it here
  # would mean reading bootstrap's configuration too.
  reference = name: entry:
    if lib.hasPrefix "op://" entry.reference then entry.reference
    else throw "secrets.nix: ${name} needs a full op:// reference to be written at activation";

  # `op read` for a field, `op document get` for a document, trimmed the way
  # bootstrap trims a field.
  fetch = name: entry:
    let
      ref = reference name entry;
      parts = lib.splitString "/" (lib.removePrefix "op://" ref);
    in
    if (entry.kind or "document") == "field" then
      "op read --no-newline ${lib.escapeShellArg ref}"
    else
      "op document get ${lib.escapeShellArg (builtins.elemAt parts 1)} --vault ${lib.escapeShellArg (builtins.head parts)}";

  write = name: entry:
    let target = "${home}/${entry.target}"; in
    ''
      if [ ! -s ${lib.escapeShellArg target} ]; then
        if value=$(${fetch name entry}); then
          mkdir -p "$(dirname ${lib.escapeShellArg target})"
          temporary=$(mktemp ${lib.escapeShellArg "${target}.XXXXXX"})
          printf '%s' "$value" > "$temporary"
          chmod ${entry.mode or "0600"} "$temporary"
          mv "$temporary" ${lib.escapeShellArg target}
          echo "secrets: wrote ~/${entry.target}"
        else
          failed+=(${lib.escapeShellArg name})
        fi
      fi
    '';

  materialize = pkgs.writeShellScript "materialize-secrets" ''
    set -u
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}:$PATH
    umask 077

    op() { ${config.onepassword.op} "$@"; }

    failed=()
    ${lib.concatStrings (lib.mapAttrsToList write entries)}
    if [ ''${#failed[@]} -gt 0 ]; then
      echo "secrets: could not read ''${failed[*]}" >&2
      exit 1
    fi
  '';
in
{
  options.secrets.files = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
    description = ''
      Absolute path of each secret file this host gets, by its name in
      bootstrap's secrets.json. A consumer checks for an entry here rather than
      naming hosts itself.
    '';
  };

  config.secrets.files = lib.mapAttrs (_: entry: "${home}/${entry.target}") entries;

  config.home.activation.secrets = lib.mkIf (entries != { }) (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${materialize} \
        || warnEcho "secrets: some files from bootstrap's secrets.json were not written. Unlock 1Password (or check the service account token on Linux) and switch again"
    ''
  );
}
