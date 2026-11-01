{ config, lib, pkgs, userName, ... }:

# The TV and the receiver on Irulan's HDMI, switched on and off with the
# machine. Irulan can't do it over HDMI-CEC: its HDMI port comes straight off
# the Intel GPU with no CEC line wired, so there is no /dev/cec to send from.
# The receiver (a Denon AVR-S570BT) has no network connection either. What
# does work is the TV: Home Assistant already controls the Frame, and the
# receiver follows the TV over their own CEC link (ARC and the Denon's HDMI
# Control). So `av` asks Home Assistant, and everything else follows.
#
# All of it is system-level, so it behaves the same at the text console, at
# the login screen and in the arcade station:
#
#   av on | off | status   by hand, from any shell
#   on                     when the login screen or the station starts, and
#                          after a resume if either is running
#   off                    before suspend and at power-off (a reboot leaves
#                          the TV alone, since the machine is coming back)

let
  inherit (lib) mkEnableOption mkOption types;

  cfg = config.av;
  token = config.onepassword.templates.home-assistant-token.path;

  av = pkgs.writeShellApplication {
    name = "av";
    runtimeInputs = [ pkgs.curl pkgs.jq ];
    text = ''
      urls=(${lib.escapeShellArgs cfg.homeAssistant})
      entity=${lib.escapeShellArg cfg.entity}

      if [ ! -r ${lib.escapeShellArg token} ]; then
        echo "av: can't read the Home Assistant token at ${token}" >&2
        exit 77
      fi
      auth="Authorization: Bearer $(tr -d '\n' < ${lib.escapeShellArg token})"

      # Each address in turn until one answers.
      request() {
        for url in "''${urls[@]}"; do
          if curl -fsS -m 8 "$@" -H "$auth" "$url$path" 2>/dev/null; then
            return 0
          fi
        done
        echo "av: no Home Assistant answered at ''${urls[*]}" >&2
        return 1
      }

      service() {
        path="/api/services/media_player/$1"
        request -o /dev/null -H "Content-Type: application/json" -d "{\"entity_id\": \"$entity\"}"
      }

      case "''${1:-}" in
        on) service turn_on ;;
        off) service turn_off ;;
        status)
          path="/api/states/$entity"
          request | jq -r '"\(.attributes.friendly_name): \(.state)" + (if .attributes.art_mode_status then ", art mode \(.attributes.art_mode_status)" else "" end)'
          ;;
        *)
          echo "usage: av on|off|status" >&2
          exit 64
          ;;
      esac
    '';
  };

  avBin = lib.getExe av;

  # A failure to reach Home Assistant must never hold up what it's attached
  # to, so every hook runs `av` with `-` and a short timeout of its own.
  quietly = action: "-${pkgs.coreutils}/bin/timeout 20 ${avBin} ${action}";
in
{
  options.av = {
    enable = mkEnableOption "switching the TV and receiver with the machine";

    homeAssistant = mkOption {
      type = types.listOf types.str;
      # Traefik's name first. The local one is there for when Traefik isn't,
      # which is the moment a power-off or a resume is most likely to meet.
      default = [ "https://home.rolfs.casa" "http://home.rolfs.lan:8123" ];
      description = "Home Assistant's base URLs, tried in order.";
    };

    entity = mkOption {
      type = types.str;
      description = "The media_player entity whose turn_on and turn_off switch the TV.";
    };
  };

  config = lib.mkIf cfg.enable {
    # By item ID rather than name: the item is "Home Assistant / Irulan", and
    # an op:// reference reads the slash as a path separator.
    onepassword.templates.home-assistant-token = {
      template = pkgs.writeText "home-assistant-token" ''
        {{ op://Secrets/7cabtl2fjogz64d6rc4pmn4ol4/credential }}
      '';
      group = "av";
      mode = "0440";
    };

    users.groups.av = { };
    users.users.${userName}.extraGroups = [ "av" ];

    environment.systemPackages = [ av ];

    systemd.services = {
      greetd.serviceConfig.ExecStartPre = [ (quietly "on") ];

      av-before-sleep = {
        description = "Turn the TV off before sleeping";
        wantedBy = [ "sleep.target" ];
        before = [ "sleep.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = quietly "off";
        };
      };

      av-after-resume = {
        description = "Turn the TV back on after a resume, if something's on screen";
        wantedBy = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" "suspend-then-hibernate.target" ];
        after = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" "suspend-then-hibernate.target" ];
        script = ''
          if systemctl is-active --quiet greetd.service arcade-station.service; then
            ${pkgs.coreutils}/bin/timeout 20 ${avBin} on || true
          fi
        '';
        serviceConfig.Type = "oneshot";
      };

      # Does nothing when started. Its stop is the hook: systemd stops it on
      # the way down, before the network it was ordered after, which is the
      # last moment Home Assistant is still reachable.
      av-at-poweroff = {
        description = "Turn the TV off at power-off";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        # A switch that touched this unit would otherwise stop it, and stopping
        # it is what turns the TV off.
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
        };
        preStop = ''
          if systemctl list-jobs --no-legend | grep -q 'reboot.target'; then
            exit 0
          fi
          ${pkgs.coreutils}/bin/timeout 20 ${avBin} off || true
        '';
      };
    } // lib.optionalAttrs (config.arcade.enable or false) {
      arcade-station.serviceConfig.ExecStartPre = [ ("+" + quietly "on") ];
    };
  };
}
