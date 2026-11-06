{ config, lib, pkgs, userName, ... }:

# Moving the TV between the emulator station and the desktop while both are
# running: `station`, `desktop`, or three quick taps of the PS button on any
# controller.
#
# Switching needs root twice over, to start a system service and to change the
# active virtual terminal. Rather than let anyone run chvt or manage units, the
# only things a user can do are start three fixed root units,
# arcade-switch@{station,desktop,toggle}, and the polkit rule names exactly
# those and only the `start` verb. Each runs one action of arcade-session and
# exits, so there's no daemon holding root on anyone's behalf, and systemd
# queues a second request behind the first instead of interleaving them.

let
  cfg = config.arcade;
  greetd = config.services.greetd.enable;
  vt = toString cfg.vt;

  session = pkgs.writeShellApplication {
    name = "arcade-session";
    runtimeInputs = [ pkgs.kbd config.systemd.package pkgs.coreutils pkgs.util-linux ]
      ++ lib.optional greetd config.programs.hyprland.package;
    text = ''
      station() {
        # A station that hit its start limit refuses a plain start until the
        # limit's minute is up; asking for it by hand should always work.
        systemctl reset-failed arcade-station.service 2>/dev/null || true
        systemctl start arcade-station.service
        chvt ${vt}
      }

      # Hyprland on tty1, the login screen's or a logged-in desktop, comes
      # back from the station's VT without a display mode: gamescope changed
      # the output while it was away, and Hyprland's backend puts off setting
      # one ("has output but state has no mode, will send a reset state event
      # later") and never does, which leaves the TV unlit. Turning its DPMS
      # off and on makes it commit a mode again (found 2026-11-06).
      wake_hyprland() {
        local active="" user uid

        # chvt returns before logind has moved the seat over.
        for _ in $(seq 20); do
          active=$(loginctl show-seat seat0 --property=ActiveSession --value)
          if [[ -n $active && $(loginctl show-session "$active" --property=TTY --value) == tty1 ]]; then
            break
          fi
          active=""
          sleep 0.1
        done
        [[ -n $active ]] || return 0

        user=$(loginctl show-session "$active" --property=Name --value)
        uid=$(loginctl show-session "$active" --property=User --value)

        as_user() {
          runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$uid" "$@"
        }

        # Hyprland's own restore runs as the VT comes back; nudge it after.
        sleep 1

        as_user hyprctl instances 2>/dev/null | while read -r label instance _; do
          [[ $label == instance ]] || continue
          instance=''${instance%:}
          as_user HYPRLAND_INSTANCE_SIGNATURE="$instance" hyprctl dispatch 'hl.dsp.dpms({ action = "off" })' >/dev/null || true
          sleep 2
          as_user HYPRLAND_INSTANCE_SIGNATURE="$instance" hyprctl dispatch 'hl.dsp.dpms({ action = "on" })' >/dev/null || true
        done || true
      }

      desktop() {
        ${lib.optionalString greetd "systemctl start greetd.service"}
        chvt 1
        ${lib.optionalString greetd "wake_hyprland"}
      }

      case "''${1:-}" in
        station) station ;;
        desktop) desktop ;;
        toggle)
          # The kernel's record of the VT on screen, not logind's, which can
          # lag a switch.
          if [[ $(< /sys/class/tty/tty0/active) == tty${vt} ]]; then
            desktop
          else
            station
          fi
          ;;
        *)
          echo "usage: arcade-session station|desktop|toggle" >&2
          exit 64
          ;;
      esac
    '';
  };

  # Commands for people. --no-block because the switch is the whole point and
  # there's nothing useful to wait for.
  command = name: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = [ config.systemd.package ];
    text = ''
      systemctl start --no-block arcade-switch@${name}.service
    '';
  };

  hotkey = pkgs.rustTool {
    name = "arcade-hotkey";
    src = ./arcade-hotkey.rs;
  };
in
lib.mkIf cfg.enable {
  environment.systemPackages = [ (command "station") (command "desktop") ];

  systemd.services."arcade-switch@" = {
    description = "Switch the TV to %i";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe session} %i";
    };
  };

  security.polkit.enable = true;
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      var units = [
        "arcade-switch@station.service",
        "arcade-switch@desktop.service",
        "arcade-switch@toggle.service",
      ];

      if (action.id == "org.freedesktop.systemd1.manage-units"
          && units.indexOf(action.lookup("unit")) >= 0
          && action.lookup("verb") == "start"
          && (subject.user == "${userName}" || subject.user == "arcade")) {
        return polkit.Result.YES;
      }
    });
  '';

  systemd.services.arcade-hotkey = {
    description = "Switch between station and desktop from a controller";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${lib.getExe hotkey} ${config.systemd.package}/bin/systemctl start --no-block arcade-switch@toggle.service";
      Restart = "always";
      RestartSec = 5;

      # Reads input devices and starts one unit. Not ProtectSystem=strict:
      # systemctl reaches systemd through a socket under /run, which that
      # would make read-only.
      ProtectHome = true;
      PrivateTmp = true;
      PrivateNetwork = true;
    };
  };
}
