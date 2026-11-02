{ config, pkgs, ... }:
let
  # The agent runs in the user session, so the log belongs under the primary
  # user's data dir rather than /var/log. Spelled out from primaryUser instead
  # of read from XDG_DATA_HOME: evaluation is pure here, so `builtins.getEnv`
  # sees an empty string and the path silently becomes /tailscale-auto, which
  # launchd cannot create and which takes the agent down with it.
  dataHome = "/Users/${config.system.primaryUser}/.local/share";
  logPath = "${dataHome}/tailscale-auto/launchd.log";

  # Connect Tailscale everywhere except at home, without touching macOS's
  # on-demand VPN machinery.
  #
  # Tailscale's own "VPN on demand" delegates the decision to NEOnDemandRule,
  # which re-evaluates on every link flap, roam and wake, routinely before the
  # tunnel has settled. When nesessionmanager tears the tunnel down out from
  # under the client, the client never runs its teardown path, so
  # 100.100.100.100 stays installed as the system resolver with nothing behind
  # it and *all* name resolution dies until the next reconnect. That is the
  # "breaks my network altogether" failure, and it is a property of who makes
  # the call, not of which rules are configured.
  #
  # So the decision is made here and applied through the client's own LocalAPI
  # (`tailscale up` / `tailscale down`), which is a graceful transition that
  # restores DNS. macOS is never asked to arbitrate, so there is nothing to
  # flap. Tailscale's built-in on-demand must be off for this to hold: see
  # the note at the bottom of this file.
  #
  # The MDM route (`AlwaysOn.Enabled` and friends) is not reachable here: the
  # client reads those keys with `-objectIsForcedForKey:` against
  # /Library/Managed Preferences/io.tailscale.ipn.macsys.plist, which is derived
  # from the SIP-protected profile store. A plain `defaults write` is ignored,
  # `profiles` has no install verb, and the device channel belongs to Kandji.
  # `tailscale syspolicy list` confirms nothing is forced today.

  # Home is fingerprinted by default-gateway IP + gateway MAC, not by SSID.
  # Since Sonoma the SSID is redacted for any process without a CoreLocation
  # grant (`ipconfig getsummary en0` prints `SSID : <redacted>`, and
  # `networksetup -getairportnetwork` lies outright with "You are not
  # associated with an AirPort network"). The gateway pair needs no
  # entitlement, is cheap enough to sample every few seconds, and keeps working
  # over Ethernet. Format is `<gateway ip>/<gateway mac>`; either MAC spelling
  # works, both sides get zero-padded before comparison.
  homeNetworks = [
    "10.10.10.10/00:08:a2:0f:b6:e6"
  ];

  # How long a network fingerprint has to hold still before it is acted on.
  # This is the whole point of the exercise: never react to a transition that is
  # still in progress.
  settleSeconds = 20;

  # Once the location is settled *and* Tailscale agrees with it, stop asking the
  # client and just re-check the gateway. Measured on this machine: the gateway
  # fingerprint costs ~35ms, a LocalAPI state query another ~39ms, so coasting
  # cuts the steady-state tick by more than half and drops the round trip
  # entirely. The cost of a longer window is that a manual toggle takes up to
  # this long to be reverted, so use `tailscale-auto pause` rather than fighting
  # it.
  reconcileSeconds = 300;

  tailscale-auto = pkgs.writeShellApplication {
    name = "tailscale-auto";
    runtimeInputs = [ pkgs.jq ];
    text = # bash
      ''
        readonly tailscale=/usr/local/bin/tailscale
        readonly settle_seconds=${toString settleSeconds}
        readonly reconcile_seconds=${toString reconcileSeconds}
        readonly home_networks=(${
          builtins.concatStringsSep " " (map (network: ''"${network}"'') homeNetworks)
        })

        state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/tailscale-auto"
        settle_file="$state_dir/settle"
        applied_file="$state_dir/applied"
        pause_file="$state_dir/paused-until"
        # launchd creates StandardOutPath but not its parent directory.
        mkdir -p "$state_dir" "${dataHome}/tailscale-auto" || true

        log() {
          printf '[%s] %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" "$*"
        }

        # The agent runs every few seconds, so anything that is not a state change
        # stays quiet unless TAILSCALE_AUTO_DEBUG is set.
        debug() {
          if [ -n "''${TAILSCALE_AUTO_DEBUG:-}" ]; then
            log "$@"
          fi
        }

        # `arp` prints MACs without leading zeros (0:8:a2:f:b6:e6), so both the
        # observed and the configured fingerprint are padded before matching.
        normalize() {
          printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | awk -F'[/:]' '{
            printf "%s", $1
            for (i = 2; i <= NF; i++) {
              octet = "0" $i
              printf "%s%s", (i == 2 ? "/" : ":"), substr(octet, length(octet) - 1)
            }
            printf "\n"
          }'
        }

        gateway_mac() {
          /usr/sbin/arp -n "$1" 2>/dev/null |
            awk '$4 ~ /^[0-9a-f]+(:[0-9a-f]+){5}$/ { print $4; exit }'
        }

        # Prints `unknown` rather than guessing whenever the picture is
        # incomplete. Callers treat that as "change nothing".
        fingerprint() {
          local gateway mac

          # -inet keeps the result colon-free so normalize() can split on ':'.
          gateway=$(/sbin/route -n get -inet default 2>/dev/null |
            awk '/gateway:/ { print $2; exit }')
          if [ -z "$gateway" ]; then
            printf 'unknown\n'
            return
          fi

          mac=$(gateway_mac "$gateway")
          if [ -z "$mac" ]; then
            # The ARP cache is usually empty for a second or two after a link change.
            /sbin/ping -c 1 -t 1 "$gateway" >/dev/null 2>&1 || true
            mac=$(gateway_mac "$gateway")
          fi
          if [ -z "$mac" ]; then
            printf 'unknown\n'
            return
          fi

          normalize "$gateway/$mac"
        }

        is_home() {
          local candidate
          for candidate in "''${home_networks[@]}"; do
            if [ "$(normalize "$candidate")" = "$1" ]; then
              return 0
            fi
          done
          return 1
        }

        # --peers=false matters more than it looks: with 549 peers the full netmap
        # is 847KB of JSON per call, versus 3.7KB without. BackendState is in
        # both.
        backend_state() {
          "$tailscale" status --json --peers=false 2>/dev/null |
            jq -r '.BackendState // "unknown"'
        }

        mark_converged() {
          printf '%s %s\n' "$1" "$2" > "$applied_file"
        }

        paused() {
          local paused_until now
          if [ ! -r "$pause_file" ]; then
            return 1
          fi
          paused_until=$(cat "$pause_file")
          now=$(date +%s)
          if [ "$now" -lt "$paused_until" ]; then
            debug "paused for another $((paused_until - now))s"
            return 0
          fi
          rm -f "$pause_file"
          log "pause expired, resuming"
          return 1
        }

        apply() {
          local now current previous since applied checked state desired

          if paused; then
            return
          fi

          current=$(fingerprint)
          if [ "$current" = unknown ]; then
            # Mid-transition: no default route, or the gateway has not answered
            # ARP yet. Doing nothing here is the point: guessing is what
            # strands the resolver.
            debug "no usable default route, leaving Tailscale alone"
            return
          fi

          now=$(date +%s)
          previous=""
          since="$now"
          if [ -r "$settle_file" ]; then
            read -r previous since < "$settle_file" || true
          fi

          if [ "$current" != "$previous" ]; then
            since="$now"
            printf '%s %s\n' "$current" "$since" > "$settle_file"
            log "network is $current, settling for ''${settle_seconds}s"
          fi

          if [ $((now - since)) -lt "$settle_seconds" ]; then
            return
          fi

          # Everything above this line is cheap and local. Below it we talk to
          # the client, so coast once this location is known to be converged.
          applied=""
          checked=0
          if [ -r "$applied_file" ]; then
            read -r applied checked < "$applied_file" || true
          fi
          if [ "$current" = "$applied" ] && [ $((now - checked)) -lt "$reconcile_seconds" ]; then
            return
          fi

          state=$(backend_state)
          case "$state" in
            Running | Stopped) ;;
            *)
              # NeedsLogin, Starting, or the system extension is down. None of
              # those are ours to arbitrate.
              debug "backend state is $state, leaving Tailscale alone"
              return
              ;;
          esac

          if is_home "$current"; then
            desired=Stopped
          else
            desired=Running
          fi

          if [ "$state" = "$desired" ]; then
            mark_converged "$current" "$now"
            return
          fi

          if [ "$desired" = Running ]; then
            log "away ($current), connecting"
            # `up` must stay bare, so the wait is bounded from outside rather
            # than with --timeout. Any flag at all, --timeout included, makes the
            # CLI treat the call as a settings change and refuse it unless every
            # non-default pref is restated, and the GUI leaves some set
            # (RouteAll, ExitNodeAllowLANAccess). A flagless `up` is the one form
            # that only sets WantRunning. Killing it on timeout reverts nothing,
            # the same as --timeout expiring.
            if ${pkgs.coreutils}/bin/timeout 30 "$tailscale" up; then
              mark_converged "$current" "$now"
            else
              # Usually an uncleared captive portal. Deliberately left unconverged
              # so the next tick retries instead of coasting for the reconcile
              # window, and nothing is half-configured in the meantime.
              log "connect failed, will retry"
            fi
          else
            log "home ($current), disconnecting"
            if "$tailscale" down; then
              mark_converged "$current" "$now"
            else
              log "disconnect failed, will retry"
            fi
          fi
        }

        case "''${1:-apply}" in
          apply)
            apply
            ;;
          pause)
            minutes="''${2:-60}"
            printf '%s\n' "$(($(date +%s) + minutes * 60))" > "$pause_file"
            log "paused for ''${minutes}m"
            ;;
          resume)
            rm -f "$pause_file"
            log "resumed"
            ;;
          status)
            current=$(fingerprint)
            printf 'network:  %s\n' "$current"
            if [ "$current" = unknown ]; then
              printf 'location: unknown\n'
            elif is_home "$current"; then
              printf 'location: home\n'
            else
              printf 'location: away\n'
            fi
            printf 'tailscale: %s\n' "$(backend_state)"
            if [ -r "$pause_file" ]; then
              printf 'paused:   until %s\n' "$(date -r "$(cat "$pause_file")")"
            else
              printf 'paused:   no\n'
            fi
            ;;
          *)
            printf 'usage: tailscale-auto [apply|pause [minutes]|resume|status]\n' >&2
            exit 2
            ;;
        esac
      '';
  };
in
{
  environment.systemPackages = [ tailscale-auto ];

  # The CLI talks to the system extension over the LocalAPI port advertised in
  # /Library/Tailscale/ipnport, authenticated by sameuserproof-<port> (root:admin
  # 0640). jamie is in admin, so this needs no root and belongs in the user
  # session rather than as a daemon.
  launchd.user.agents.tailscale-auto = {
    serviceConfig = {
      ProgramArguments = [
        "${tailscale-auto}/bin/tailscale-auto"
        "apply"
      ];

      # configd rewrites resolv.conf on every network change, so a join or leave
      # is noticed immediately instead of at the next tick. StartInterval is
      # what actually applies the decision once the settle window has elapsed,
      # and doubles as the backstop if the kqueue watch is lost to an atomic
      # replace of the file.
      WatchPaths = [ "/var/run/resolv.conf" ];
      StartInterval = 10;
      ThrottleInterval = 5;

      RunAtLoad = true;
      ProcessType = "Background";
      StandardOutPath = logPath;
      StandardErrorPath = logPath;
    };
  };

  # One manual step, in the same class as the Full Disk Access grant for
  # icon-customizer: turn Tailscale's own on-demand off, in System Settings →
  # VPN → Tailscale (ⓘ) → uncheck "Connect on demand". Leaving it on puts
  # NEOnDemandRule back in the loop and reintroduces exactly the flap this
  # replaces. Verify with `scutil --nc list` showing the Tailscale service and
  # `tailscale-auto status` reporting the expected location.
}
