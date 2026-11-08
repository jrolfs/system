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
#   on                     when the keyboard or trackpad is used after a while
#                          idle, a controller's PS button is tapped, or one
#                          connects
#   off                    on Hyper+Escape from any keyboard
#   off --automatic        when the last controller has been gone a while,
#                          if the arcade station is on screen
#
# The second and third only with `av.automatic`, the fourth only with
# `av.wake`, and the last two with `av.off.key` and `av.off.controllers`. The
# desktop's power menu has a TV Off as well, which is `av off`.
#
# Turning on takes more than the TV's turn_on when the Frame is fully off, or
# when the Apple TV beside Irulan has taken the receiver. With `av.onScript`
# set, `on` starts that Home Assistant script instead and returns at once.
# Turning off wants less than turn_off, which on a Frame holds the power button
# and switches it fully off, past art mode. With `av.offScript` set, `off`
# starts that script instead, and `--automatic` tells it nobody asked, so it
# can decline. Irulan's are in
# services/home-assistant/packages/living_room.yaml.
#
# `av.wake` exists because `av.automatic` turned the TV on whenever a session
# started, and a crash-looping station started one every two seconds. Waking on
# someone picking up an input device asks for the TV only when it's wanted, and
# av-input.rs holds back while the devices are in use.

let
  inherit (lib) mkEnableOption mkOption types;

  cfg = config.av;
  token = config.onepassword.templates.home-assistant-token.path;

  orEmpty = value: lib.escapeShellArg (if value == null then "" else value);

  # Its modification time is the last time someone turned the TV off, which
  # av-input reads. Group av can write it, so an `av off` typed or clicked
  # counts the same as one from a root service.
  marker = "/run/av/off";

  av = pkgs.writeShellApplication {
    name = "av";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.jq ];
    text = ''
      urls=(${lib.escapeShellArgs cfg.homeAssistant})
      entity=${lib.escapeShellArg cfg.entity}
      on_script=${orEmpty cfg.onScript}
      off_script=${orEmpty cfg.offScript}

      usage() {
        echo "usage: av on | off [--automatic] | status" >&2
        exit 64
      }

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

      # script.turn_on returns as soon as the script has started.
      start() {
        path="/api/services/script/turn_on"
        request -o /dev/null -H "Content-Type: application/json" -d "$1"
      }

      case "''${1:-}" in
        on)
          if [ -n "$on_script" ]; then
            start "{\"entity_id\": \"$on_script\"}"
          else
            service turn_on
          fi
          ;;
        off)
          automatic=false
          case "''${2:-}" in
            "") ;;
            --automatic) automatic=true ;;
            *) usage ;;
          esac

          if [ -n "$off_script" ]; then
            start "{\"entity_id\": \"$off_script\", \"variables\": {\"automatic\": $automatic}}"
          else
            service turn_off
          fi

          # Not for an automatic off, which the script may have declined:
          # the next keypress would then take the receiver from whatever
          # kept the TV on.
          if [ "$automatic" = false ]; then
            (umask 002 && touch ${marker}) 2>/dev/null || true
          fi
          ;;
        status)
          path="/api/states/$entity"
          request | jq -r '"\(.attributes.friendly_name): \(.state)" + (if .attributes.art_mode_status then ", art mode \(.attributes.art_mode_status)" else "" end)'
          ;;
        *) usage ;;
      esac
    '';
  };

  avBin = lib.getExe av;

  input = pkgs.rustTool {
    name = "av-input";
    src = ./av-input.rs;
  };

  inputArguments = [ "--marker" marker ]
    ++ lib.optionals cfg.wake.enable [
      "--wake"
      "--idle" (toString cfg.wake.idle)
      "--cooldown" (toString cfg.wake.cooldown)
    ]
    ++ lib.optional cfg.off.key "--off-key"
    ++ lib.optionals (cfg.off.controllers != null) (
      [ "--controllers-gone" (toString cfg.off.controllers) ]
      ++ lib.optionals (config.arcade.enable or false) [ "--vt" (toString config.arcade.vt) ]
    );

  # A failure to reach Home Assistant must never hold up what it's attached
  # to, so every hook runs `av` with `-` and a short timeout of its own.
  quietly = action: "-${pkgs.coreutils}/bin/timeout 20 ${avBin} ${action}";
in
{
  options.av = {
    enable = mkEnableOption "switching the TV and receiver with the machine";

    package = mkOption {
      type = types.package;
      readOnly = true;
      internal = true;
      default = av;
      description = "The `av` command, for other modules to run.";
    };

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

    automatic = mkOption {
      type = types.bool;
      default = true;
      description = "Switch the TV with the sessions, suspend and power-off, rather than only by hand.";
    };

    onScript = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "script.irulan_on_tv";
      description = ''
        A Home Assistant script that `av on` starts in place of the entity's
        turn_on, for whatever else getting Irulan's picture on screen takes.
      '';
    };

    offScript = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "script.irulan_off_tv";
      description = ''
        A Home Assistant script that `av off` starts in place of the entity's
        turn_off. It gets an `automatic` variable, true when nobody asked for
        the off, so that it can decline.
      '';
    };

    wake = {
      enable = mkEnableOption "turning the TV on when a keyboard, trackpad or controller is picked up";

      idle = mkOption {
        type = types.ints.positive;
        default = 300;
        description = ''
          Seconds without a key press, click or touch after which the next one
          turns the TV on. Typing or using the trackpad in the meantime never
          does, except for the first press ten seconds or more after someone
          turns the TV off. A tap of a controller's PS button or a
          controller connecting always counts.
        '';
      };

      cooldown = mkOption {
        type = types.ints.positive;
        default = 30;
        description = "Seconds after turning the TV on before anything can again.";
      };
    };

    off = {
      key = mkEnableOption ''
        turning the TV off with Hyper+Escape (Ctrl, Alt, Shift and Super, then
        Escape) on any keyboard, at the console, the login screen, the desktop
        or the arcade station
      '';

      controllers = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        example = 30;
        description = ''
          Seconds after the last controller disconnects before turning the TV
          off, or null to leave it on. Only while the arcade station is on
          screen, where there is one. This is `av off --automatic`, so
          `offScript` can decline.
        '';
      };
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

    systemd.tmpfiles.rules = [ "d ${dirOf marker} 2770 root av -" ];

    environment.systemPackages = [ av ];

    systemd.services = lib.mkMerge [ (lib.mkIf cfg.automatic ({
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
    }))

    (lib.mkIf (cfg.wake.enable || cfg.off.key || cfg.off.controllers != null) {
      av-input = {
        description = "Turn the TV on and off as the keyboard, trackpad and controllers are picked up and put down";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "${lib.getExe input} ${lib.escapeShellArgs inputArguments} -- ${avBin}";
          Restart = "always";
          RestartSec = 5;

          # Root, to read every input device the way arcade-hotkey does. It
          # only reads them and makes requests to Home Assistant, so it gets
          # no view of /home and a /tmp of its own.
          ProtectHome = true;
          PrivateTmp = true;
        };
      };
    }) ];
  };
}
