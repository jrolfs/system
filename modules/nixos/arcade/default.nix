{ config, lib, pkgs, utils, userName, ... }:

# The emulator station: a game menu on the TV, run by its own `arcade` user so
# whoever is holding the controller can't reach anything of Jamie's.
#
# Pegasus runs fullscreen inside gamescope, Valve's compositor for exactly this
# kind of single-app TV session, and launches each game in RetroArch with the
# core for its system. The station is a systemd service on its own virtual
# terminal rather than a second greetd session, so it and the desktop on tty1
# can both stay running and switching between them is a VT switch: instant,
# and neither loses its state (see switch.nix).
#
# Games live outside the arcade user's home, in a directory shared with Jamie
# through the `arcade` group, so ROMs can be copied in and scraped from an SSH
# session without becoming the arcade user. Layout and the BIOS files each
# system needs are in documentation/ARCADE.md.

let
  inherit (lib) mkEnableOption mkIf mkOption types;

  cfg = config.arcade;
  systems = import ./systems.nix;

  cores = lib.unique (lib.mapAttrsToList (_: system: pkgs.libretro.${system.core}) systems);

  # A core's library, by the naming mkLibretroCore installs it under.
  coreLibrary = core:
    let package = pkgs.libretro.${core};
    in "${package}${package.libretroCore}/${builtins.replaceStrings [ "-" ] [ "_" ] package.core}_libretro.so";

  # RetroArch with no cores of its own. Each launch names its core explicitly
  # (-L in the launch line), which the stock withCores wrapper doesn't suit: it
  # bakes a -L for every core into the binary. The cores are still listed for
  # RetroArch's own menu through libretro_directory.
  retroarch = pkgs.retroarch-bare.wrapper {
    settings = {
      libretro_directory = "${pkgs.symlinkJoin { name = "arcade-cores"; paths = cores; }}/lib/retroarch/cores";
      system_directory = "${cfg.root}/bios";
      savefile_directory = "${cfg.root}/saves";
      savestate_directory = "${cfg.root}/states";
      screenshot_directory = "${cfg.root}/screenshots";

      video_fullscreen = "true";

      # A saved PulseAudio sink name is not an ALSA PCM device. Keep the driver
      # and device selection together, following the arcade user's default sink.
      audio_driver = "pulse";
      audio_device = "";

      # Start+Select quits back to the game menu. The PS button stays RetroArch's
      # own menu, through the controller's autoconfig profile.
      input_quit_gamepad_combo = "4";
      input_autodetect_enable = "true";
    };
  };
in
{
  imports = [
    ./controllers.nix
    ./pegasus.nix
    ./scrape.nix
    ./sessions.nix
    ./switch.nix
  ];

  options.arcade = {
    enable = mkEnableOption "the emulator station";

    root = mkOption {
      type = types.str;
      default = "/srv/arcade";
      description = "Games, BIOS files, saves and scraped media.";
    };

    vt = mkOption {
      type = types.int;
      default = 7;
      description = ''
        Virtual terminal the station runs on. Not 1, which is the desktop's, and
        above logind's six automatic login terminals, so nothing else claims it.
      '';
    };

    launch = mkOption {
      type = types.attrsOf types.str;
      readOnly = true;
      internal = true;
      description = "Launch line per system, shared by Pegasus and Skyscraper.";
      default = lib.mapAttrs
        (_: system: ''${lib.getExe retroarch} -L ${coreLibrary system.core} "{file.path}"'')
        systems;
    };
  };

  config = mkIf cfg.enable {
    users.groups.arcade = { };

    users.users.arcade = {
      isNormalUser = true;
      group = "arcade";
      description = "Emulator station";
      # Locked: nothing logs in as arcade. The station's service opens its
      # session through PAM's account and session stages, which never ask.
      hashedPassword = "!";
      extraGroups = [ "input" "video" "render" ];
    };

    # Jamie can add ROMs and run arcade-scrape without becoming arcade.
    users.users.${userName}.extraGroups = [ "arcade" ];

    # setgid so everything created underneath stays group arcade, whoever
    # created it.
    systemd.tmpfiles.rules = [
      "d ${cfg.root} 2775 arcade arcade - -"
      "d ${cfg.root}/roms 2775 arcade arcade - -"
      "d ${cfg.root}/bios 2775 arcade arcade - -"
      "d ${cfg.root}/saves 2775 arcade arcade - -"
      "d ${cfg.root}/states 2775 arcade arcade - -"
      "d ${cfg.root}/screenshots 2775 arcade arcade - -"
    ] ++ lib.mapAttrsToList (name: _: "d ${cfg.root}/roms/${name} 2775 arcade arcade - -") systems;

    environment.systemPackages = [ retroarch ];

    programs.gamescope.enable = true;

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };
    security.rtkit.enable = true;

    # Mirrors NixOS's cage kiosk service (nixos/modules/services/wayland/cage.nix),
    # with gamescope in place of cage and a VT other than 1. The PAM session is
    # what makes this a real logind session on seat0: gamescope gets DRM and
    # input through it, and the arcade user's PipeWire starts with it.
    systemd.services.arcade-station = {
      description = "Emulator station";
      after = [
        "systemd-user-sessions.service"
        "systemd-logind.service"
        "plymouth-quit.service"
        "getty@tty${toString cfg.vt}.service"
      ];
      wants = [ "dbus.socket" "systemd-logind.service" ];
      conflicts = [ "getty@tty${toString cfg.vt}.service" ];

      unitConfig = {
        ConditionPathExists = "/dev/tty${toString cfg.vt}";
        # Restart = "always" (below) on its own retries a crash that recurs
        # forever. On 2026-11-04 that was about 150 restarts in seven minutes,
        # each turning the TV back on through `av on`: Pegasus died when a
        # DualSense reconnected, and every restart came up on a background VT
        # with no input devices, which gamescope won't start without. So five
        # tries a minute, then it stays down until `station`.
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };

      environment = {
        # Read by pam_systemd for the logind session's type.
        XDG_SESSION_TYPE = "wayland";
        # gamescope gives the app inside it an X display through Xwayland and
        # no Wayland socket, so Qt shouldn't go looking for one.
        QT_QPA_PLATFORM = "xcb";
      };

      serviceConfig = {
        ExecStart = "${lib.getExe config.programs.gamescope.package} --backend drm --fullscreen -- ${lib.getExe pkgs.pegasus-frontend}";
        User = "arcade";
        PAMName = "arcade-station";

        # Quitting Pegasus from its menu shouldn't leave a dead TV.
        Restart = "always";
        RestartSec = 2;

        UtmpIdentifier = "%n";
        UtmpMode = "user";
        TTYPath = "/dev/tty${toString cfg.vt}";
        TTYReset = "yes";
        TTYVHangup = "yes";
        TTYVTDisallocate = "yes";
        StandardInput = "tty-fail";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # cage's rule set, minus `auth`: systemd's PAMName only runs the account and
    # session stages, so nothing here ever asks for the locked password.
    # pam_systemd is the one that matters, registering the logind session.
    security.pam.services.arcade-station = {
      useDefaultRules = false;
      rules = {
        account = utils.pam.autoOrderRules [
          {
            name = "unix";
            control = "required";
            modulePath = config.security.pam.pam_unixModulePath;
          }
        ];
        session = utils.pam.autoOrderRules [
          {
            name = "unix";
            control = "required";
            modulePath = config.security.pam.pam_unixModulePath;
          }
          {
            name = "env";
            control = "required";
            modulePath = "${config.security.pam.package}/lib/security/pam_env.so";
            settings.conffile = "/etc/pam/environment";
            settings.readenv = 0;
          }
          {
            name = "systemd";
            control = "required";
            modulePath = "${config.systemd.package}/lib/security/pam_systemd.so";
          }
        ];
      };
    };
  };
}
