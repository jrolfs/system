{ config, lib, pkgs, ... }:

# One Full Disk Access grant, shared by everything that needs one.
#
# TCC evaluates a grant against the Mach-O binary being executed, so FDA cannot
# be given to a shell script (the grant lands on /bin/bash) nor to a nix store
# path (which moves on every rebuild). The grant therefore sits on a single
# compiled shim at a fixed /usr/local/bin path, and every operation needing that
# access is reached through it. Each new FDA-hungry tool would otherwise cost
# another manual approval, and nix-darwin's activation cannot stand in for one:
# it writes user defaults through `launchctl asuser ... sudo --user=...`, which
# holds no grant of its own.
#
# The shim is ad-hoc signed, so TCC has no stable signing identity to key the
# grant on and falls back to the cdhash, a hash of the binary's bytes. Any
# rebuild that perturbs them revokes the grant, silently. That is a real
# recurring failure rather than a theoretical one, and it used to surface only
# as icons mysteriously no longer updating, which is why the dispatcher probes
# for the grant and announces its absence instead of failing mutely. Signing the
# shim with a stable identity would fix the revocation at the root, but that
# needs a trusted certificate in the System keychain and so belongs with the
# bootstrap chain in documentation/SECRETS.md.

let
  cfg = config.fda;
  user = config.system.primaryUser;

  shim = pkgs.rustTool {
    name = "fda-run";
    src = ./pkgs/fda-run.rs;
  };

  shimAgentLabels = lib.pipe config.launchd.user.agents [
    lib.attrValues
    (lib.filter (agent:
      lib.take 1 (lib.toList agent.serviceConfig.ProgramArguments) == [ cfg.runPath ]))
    (map (agent: agent.serviceConfig.Label))
  ];

  # One `case` arm per registered operation. An allowlist rather than passing
  # the command line through: anything able to exec the shim can reach whatever
  # it will run, so letting it run arbitrary commands would turn it into a
  # general-purpose way to borrow Full Disk Access.
  cases = lib.concatStringsSep "\n"
    (lib.mapAttrsToList
      (name: package: "  ${name}) runner=${lib.getExe package} ;;")
      cfg.operations);

  dispatch = pkgs.writeShellScriptBin "fda-dispatch" # bash
    ''
      set -eu

      # Nothing answers "do I have Full Disk Access?", so probe by reading a
      # file only the grant can open. It has to be a real open: access(2), and
      # so `test -r`, consults the POSIX bits alone and calls a TCC-protected
      # file readable. TCC.db is the right file to probe because FDA is the one
      # permission macOS never prompts for, making a denial a silent EPERM.
      # Probing Documents or Desktop would raise a consent dialog out of a
      # background LaunchAgent instead.
      hasFullDiskAccess() {
        head -c 1 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
          >/dev/null 2>&1
      }

      # Debounced to once a day. The icons agent watches /Applications, so an
      # ungranted machine would otherwise notify on every app install and every
      # switch; ThrottleInterval does not help, it only spaces the runs out.
      reportMissingAccess() {
        stamp="/tmp/fda-run-nag.$(id -u)"
        if [ -f "$stamp" ] \
          && [ "$(( $(date +%s) - $(stat -f %m "$stamp") ))" -lt 86400 ]
        then
          return 0
        fi
        : > "$stamp"

        # The URL only opens the pane. macOS has no API to request Full Disk
        # Access the way Accessibility can be requested, so a human still has to
        # add the binary, and the pane gives no hint as to which one wanted it.
        # Hence naming the exact path in the message.
        ${lib.getExe pkgs.terminal-notifier} \
          -title "Full Disk Access needed" \
          -message "Add ${cfg.runPath} in Privacy & Security, then retry." \
          -execute 'open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"'
      }

      operation="''${1-}"
      if [ "$#" -gt 0 ]; then shift; fi

      case "$operation" in
      ${cases}
        *)
          echo "fda-dispatch: unknown operation '$operation'" >&2
          exit 64
          ;;
      esac

      if ! hasFullDiskAccess; then
        reportMissingAccess
        echo "fda-dispatch: no Full Disk Access, skipping $operation" >&2
        exit 77
      fi

      exec "$runner" "$@"
    '';
in
{
  options.fda = {
    operations = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      default = { };
      example = lib.literalExpression ''{ icons = pkgs.icon-customizer; }'';
      description = ''
        Operations reachable through the Full Disk Access shim, keyed by the
        name it is invoked with. Each package's main program runs with the grant
        in place, with any remaining arguments forwarded to it.
      '';
    };

    runPath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "/usr/local/bin/fda-run";
      description = ''
        Where the shim is installed, and so the path a human adds to Full Disk
        Access in System Settings. Moving it costs everyone a re-approval.
      '';
    };
  };

  config = {
    environment.systemPackages = [ dispatch ];

    system.activationScripts.postActivation.text = lib.mkAfter # bash
      ''
        mkdir -p /usr/local/bin

        if ! cmp -s ${shim}/bin/fda-run ${cfg.runPath}; then
          # Renamed into place rather than written over the old file. The kernel
          # caches a binary's code signature against its vnode, so new bytes in
          # the same file can get the next launch killed as invalidly signed.
          cp ${shim}/bin/fda-run ${cfg.runPath}.new
          chmod 0555 ${cfg.runPath}.new
          mv -f ${cfg.runPath}.new ${cfg.runPath}

          # New bytes also strand every loaded agent whose program is the shim.
          # launchd keeps a code requirement per job, sourced from Background
          # Task Management, and for an ad-hoc signed binary that is the cdhash.
          # Once it changes, launchd asks BTM for a fresh one under an item UUID
          # BTM has since replaced, and every spawn then exits 78 (EX_CONFIG)
          # before the shim runs, so the dispatcher never gets to report the
          # lost grant. nix-darwin only reloads an agent whose plist changed, and
          # these plists don't. Reloading them also lets the RunAtLoad ones probe
          # straight away, so a lost grant is announced at switch time.
          uid=$(id -u -- ${user})
          agents=~${user}/Library/LaunchAgents
          for label in ${lib.escapeShellArgs shimAgentLabels}; do
            [ -f "$agents/$label.plist" ] || continue
            launchctl asuser "$uid" sudo --user=${user} -- \
              launchctl bootout "gui/$uid/$label" 2>/dev/null || true
            launchctl asuser "$uid" sudo --user=${user} -- \
              launchctl bootstrap "gui/$uid" "$agents/$label.plist" \
              || echo "fda: could not reload $label, log out and back in to recover it" >&2
          done
        fi

        # The shim this one replaces. Left in place it would be a second binary
        # holding Full Disk Access that nothing calls any more, so the stale
        # entry wants deleting from System Settings too.
        rm -f /usr/local/bin/icon-customizer
      '';
  };
}
