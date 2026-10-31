{ config, lib, pkgs, ... }:

# Home Assistant and the Matter server as native services, taking over from
# Leia's containers in phase 4 of documentation/IRULAN-MIGRATION.md, which
# also has the cutover runbook.
#
# Off until the cutover. Turning it on beside Leia's instance is the dry run
# the plan calls for: an empty /var/lib/hass proves every integration below
# loads. Taking 10.10.10.2 is a separate option because Leia's Home Assistant
# holds that address until it is stopped.
#
# The integrations are the ones Leia's instance had config entries for in
# October 2026, plus what its YAML uses. Components the config below names are
# found by the module on its own; everything configured through the UI or a
# package has to be listed, or its Python dependencies are missing and the
# integration fails to load.

let
  cfg = config.homeAssistant;

  configDir = config.services.home-assistant.configDir;

  custom = pkgs.callPackage ./custom-components.nix { };

  # Traefik, which still runs on Leia, sends X-Forwarded-For.
  traefik = "10.10.10.12";

  # One port per HomeKit Bridge entry. Fourteen are in use, from 21064 up;
  # 21063 is the default for the next one created.
  homekitPorts = {
    from = 21063;
    to = 21081;
  };
in
{
  options.homeAssistant = {
    enable = lib.mkEnableOption "Home Assistant and the Matter server";

    serveLegacyAddress = lib.mkEnableOption ''
      10.10.10.2, Home Assistant's address on Leia, as a second address on
      enp3s0. Device integrations, the companion apps and Traefik's route all
      know Home Assistant by it. Only once Leia's instance is stopped: the
      same address on both hosts is an IP conflict
    '';
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.home-assistant = {
        enable = true;

        extraComponents = [
          # Config entries on Leia.
          "analytics"
          "apple_tv"
          "backblaze_b2"
          "backup"
          "broadlink"
          "dlna_dmr"
          "go2rtc"
          "google_translate"
          "group"
          "homekit"
          "hue"
          "lifx"
          "lutron_caseta"
          "matter"
          "met"
          "mobile_app"
          "radio_browser"
          "shelly"
          "shopping_list"
          "sun"
          "switchbot_cloud"
          "thread"
          "tplink"
          "upnp"
          "wake_on_lan"
          "wemo"
          "yoto"

          # Their entries are disabled on Leia but still exist, and a
          # disabled entry whose integration can't load can't be re-enabled.
          "samsungtv"
          "smartthings"

          # packages/hatch.yaml, which the module can't see into.
          "template"
          "universal"

          # dyson_local declares these as dependencies, and gets paho-mqtt
          # through mqtt.
          "mqtt"
          "zeroconf"
        ];

        # HACS isn't carried over: it installs into custom_components at
        # runtime, which here belongs to the module and is rebuilt from this
        # list. Leia's humidity_intelligence isn't either, since it has no
        # config entry there, only leftover entities.
        customComponents = [
          pkgs.home-assistant-custom-components.samsungtv-smart
          custom.dyson-local
          custom.ha-hatch
        ];

        # Translated from rolfs.lan's tracked configuration.yaml. Strings
        # starting with "!" are written out as YAML tags, so the includes stay
        # includes and the UI keeps editing automations.yaml, scripts.yaml and
        # scenes.yaml in the config directory.
        config = {
          # default_config's integrations, listed out (from its manifest in
          # this Home Assistant release) so bluetooth can be left off. It would
          # claim the adapter Irulan's keyboard, trackpad and controllers use,
          # and Leia's Home Assistant never had Bluetooth. Re-check the list
          # against default_config's manifest when Home Assistant updates.
          assist_pipeline = { };
          cloud = { };
          conversation = { };
          dhcp = { };
          energy = { };
          file = { };
          go2rtc = { };
          history = { };
          homeassistant_alerts = { };
          logbook = { };
          media_source = { };
          mobile_app = { };
          my = { };
          ssdp = { };
          stream = { };
          sun = { };
          usage_prediction = { };
          usb = { };
          webhook = { };
          zeroconf = { };

          homeassistant.packages = "!include_dir_named ${./packages}";

          http = {
            use_x_forwarded_for = true;
            trusted_proxies = [ traefik ];
          };

          automation = "!include automations.yaml";
          script = "!include scripts.yaml";
          scene = "!include scenes.yaml";
        };
      };

      # The includes above fail to load if their file doesn't exist, which is
      # the case in the dry run's empty config directory. tmpfiles writes the
      # content only when creating the file, so the cutover's copies survive.
      systemd.tmpfiles.rules = [
        "f ${configDir}/automations.yaml 0644 hass hass - []"
        "f ${configDir}/scripts.yaml 0644 hass hass - {}"
        "f ${configDir}/scenes.yaml 0644 hass hass - []"
      ];

      # Python Matter Server, the same version as Leia's container. Home
      # Assistant reaches it at ws://localhost:5580/ws, so its port stays
      # closed to the LAN.
      services.matter-server = {
        enable = true;

        # The module passes Home Assistant's vendor ID, 4939. Leia's container
        # ran with the server's default, 65521, and the fabric its devices
        # are commissioned into was created with that. extraArgs is applied
        # after the module's own arguments, so this one wins.
        extraArgs.vendorid = "65521";
      };

      networking.firewall = {
        allowedTCPPorts = [ 8123 ];
        allowedTCPPortRanges = [ homekitPorts ];

        # mDNS, which HomeKit, Apple TV, Lutron, Matter and the zeroconf
        # discoveries all run on.
        allowedUDPPorts = [ 5353 ];

        # Replies to SSDP searches (upnp, dlna_dmr, discovery) come back
        # unicast from port 1900 to whatever port the search left from, and
        # connection tracking doesn't relate them to a multicast request.
        extraCommands = ''
          iptables -A nixos-fw -p udp -s 10.10.10.0/24 --sport 1900 -j nixos-fw-accept
        '';
      };
    }

    # Keeps Home Assistant off Irulan's own Bluetooth adapter, which the
    # keyboard, trackpad and controllers use. Leaving bluetooth out of the
    # config isn't enough: shelly lists it as a dependency, so it loads anyway
    # (for Shelly devices acting as Bluetooth proxies over the network, which
    # this doesn't affect). Local adapters are reached through BlueZ on the
    # system bus, so the hass user is refused that, and raw HCI sockets too.
    {
      systemd.services.home-assistant.serviceConfig.RestrictAddressFamilies =
        lib.mkForce [ "AF_INET" "AF_INET6" "AF_NETLINK" "AF_UNIX" "AF_PACKET" ];

      services.dbus.packages = [
        (pkgs.writeTextDir "share/dbus-1/system.d/home-assistant-no-bluez.conf" ''
          <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
            "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
          <busconfig>
            <policy user="hass">
              <deny send_destination="org.bluez"/>
            </policy>
          </busconfig>
        '')
      ];
    }

    (lib.mkIf cfg.serveLegacyAddress {
      networking.interfaces.enp3s0.ipv4.addresses = [
        {
          address = "10.10.10.2";
          prefixLength = 24;
        }
      ];
    })
  ]);
}
